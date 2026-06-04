# Background Merge Fine-Tuning — Proton vs. ClickHouse

A practical reference for tuning MergeTree background merges in Timeplus Proton, with
exact defaults and how they diverge from upstream ClickHouse. All defaults verified
against source on 2026-06-04.

- Proton pools:  `src/Core/ServerSettings.h`
- Proton merge:  `src/Storages/MergeTree/MergeTreeSettings.h` (`M(...)` macro)
- Upstream pools: `~/code/ClickHouse/src/Core/ServerSettings.cpp`
- Upstream merge: `~/code/ClickHouse/src/Storages/MergeTree/MergeTreeSettings.cpp` (`DECLARE(...)` macro)

> Proton is a fork of an older ClickHouse, so several merge-related defaults are the
> *pre-23.6* values. The divergences are not cosmetic — they make Proton **throttle
> inserts ~10× sooner** than current ClickHouse. See [§7](#7-proton-vs-upstream-divergences).

---

## 1. Mental model

Inserts always create new parts on the **hot tier / first volume**. A background loop
periodically *selects* a range of parts in a partition and *merges* them into one larger
part. Merges run on a shared, server-wide thread pool. Two failure modes drive all tuning:

1. **Merges fall behind inserts** → active part count per partition climbs → first
   inserts are *delayed*, then *rejected* with `TOO_MANY_PARTS`.
2. **Merges are too aggressive / too large** → CPU + IO (and, on S3 tiers, request cost
   and write amplification) spike.

There are two distinct layers of settings:

| Layer | Where | Scope | When applied |
|---|---|---|---|
| **Pool sizing** | `ServerSettings` | Server-wide, all tables | **Startup only** (config.xml) |
| **Merge behavior** | `MergeTreeSettings` | Per-table (overridable) | Live (`ALTER TABLE ... MODIFY SETTING`) or per-table `SETTINGS` |

---

## 2. Pool sizing (server-level, startup only)

These live in the `<merge_tree>` / profile section of the server config and **only take
effect at restart**. The merge pool is **shared across every MergeTree table** and handles
**both merges and mutations**.

| Setting | Proton | Upstream | Notes |
|---|---|---|---|
| `background_pool_size` | **16** | **16** | Threads for merges + mutations |
| `background_merges_mutations_concurrency_ratio` | **2** | **2** | Tasks ÷ threads → up to **32 concurrent** tasks with 16 threads |
| `background_merges_mutations_scheduling_policy` | `round_robin` | `round_robin` | `round_robin` = fairness; `shortest_task_first` = better throughput, can starve big merges |
| `background_move_pool_size` | **8** | **8** | TTL / `move_factor` moves to other disks/volumes (this is what feeds an S3 tier) |
| `background_fetches_pool_size` | **8** ⚠ | **16** | Replica part fetches |
| `background_common_pool_size` | **8** | **8** | GC / housekeeping (old-part removal, etc.) |
| `background_schedule_pool_size` | **16** ⚠ | **512** | Lightweight periodic tasks (replication, streaming, DNS). Big gap. |

**Effective concurrent merges = `background_pool_size × concurrency_ratio` = 32** (default).

The `concurrency_ratio > 1` trick works because background tasks can be *suspended and
postponed* — it lets many small, fast merges get scheduled ahead of a few huge ones
instead of 16 giant merges monopolizing all threads.

> **Tuning the pool:** increase `background_pool_size` (e.g. 32–64) only on machines with
> spare cores **and** IO headroom when merges genuinely can't keep up. More threads on an
> IO-bound box just thrashes. The pool is shared, so this affects every table.

---

## 3. Merge selection & sizing (per-table)

Controls *which* parts get merged and *how big* a merge may be.

| Setting | Proton | Upstream | Meaning |
|---|---|---|---|
| `max_bytes_to_merge_at_max_space_in_pool` | **150 GiB** | **150 GiB** | Largest merge when the pool is idle. The effective cap on final part size. |
| `max_bytes_to_merge_at_min_space_in_pool` | **1 MiB** | **1 MiB** | Largest merge when the pool is nearly full (back-pressure) |
| `number_of_free_entries_in_pool_to_lower_max_size_of_merge` | **8** | **8** | Below this many free slots, shrink max merge size so small merges still run (anti-starvation) |
| `max_parts_to_merge_at_once` | **100** | **100** | Cap on parts per single merge (0 = unlimited; doesn't affect `OPTIMIZE FINAL`) |
| `merge_selector_algorithm` | *absent* ⚠ | `SIMPLE` | Newer CH selector knob; Proton uses the legacy Simple selector implicitly |
| `merge_selector_base` | *absent* ⚠ | `5.0` | Newer CH write-amplification dial; not present in Proton |
| `min_merge_bytes_to_use_direct_io` | **10 GiB** | **10 GiB** | Above this merge size, use `O_DIRECT` (bypass page cache). 0 = never. |
| `ratio_of_defaults_for_sparse_serialization` | **0.9375** | **0.9375** | Sparse-column threshold during merge writes |

`max_bytes_to_merge_at_*` interpolate by pool fullness: a fully-idle pool will merge up to
150 GiB; as free slots shrink toward `number_of_free_entries_in_pool_to_lower_max_size_of_merge`,
the allowed merge size drops toward 1 MiB. This is the self-balancing mechanism that keeps
small merges flowing under load.

### Merge algorithm (vertical vs horizontal)

| Setting | Proton | Upstream | Meaning |
|---|---|---|---|
| `enable_vertical_merge_algorithm` | **1** | **1** | Merge PK/sort columns first, then remaining columns separately (lower memory) |
| `vertical_merge_algorithm_min_rows_to_activate` | **131072** (16×8192) | same | Min rows to use vertical merge |
| `vertical_merge_algorithm_min_bytes_to_activate` | **0** | same | Min bytes to use vertical merge |
| `vertical_merge_algorithm_min_columns_to_activate` | **11** | same | Min non-PK columns to use vertical merge |
| `vertical_merge_remote_filesystem_prefetch` | **true** | same | Prefetch next column from remote FS during vertical merge |
| `max_merge_delayed_streams_for_parallel_write` | **40** | same | Caps in-flight column streams during vertical merge to **remote/parallel-write disks (S3)** — bounds memory amplification for wide schemas |

---

## 4. TTL merges (tiering & expiry)

| Setting | Proton | Upstream | Meaning |
|---|---|---|---|
| `max_number_of_merges_with_ttl_in_pool` | **2** | **2** | Cap on concurrent TTL merges; leaves threads for regular merges to avoid "too many parts" |
| `merge_with_ttl_timeout` | **14400** (4 h) | same | Min seconds between repeated **delete-TTL** merges on a range |
| `merge_with_recompression_ttl_timeout` | **14400** (4 h) | same | Min seconds between repeated **recompression-TTL** merges |
| `max_replicated_merges_with_ttl_in_queue` | **1** | — | (Replicated) concurrent TTL merges in queue |
| `ttl_only_drop_parts` | **false** | same | If true, only drop whole expired parts; don't partially rewrite a part to prune rows. **Set true for time-partitioned tables** → expiry becomes a cheap part drop instead of a rewrite. |

> For S3 tiering, the moves themselves are driven by **MOVE TTL** (`TO VOLUME 'cold'`) +
> `background_move_pool_size`, not the merge pool. The `merge_with_ttl_timeout` only
> governs *delete*-TTL merge cadence. See the storage-policy notes in [§8](#8-tuning-playbook).

---

## 5. Insert throttling — the "too many parts" guardrails

These are the symptoms you hit when merges fall behind. Evaluated **per partition, on
active parts** (except `max_parts_in_total`, which is global).

| Setting | Proton | Upstream | Meaning |
|---|---|---|---|
| `parts_to_delay_insert` | **150** ⚠ | **1000** | Above this many active parts in a partition, inserts are *artificially delayed* |
| `parts_to_throw_insert` | **300** ⚠ | **3000** | Above this, inserts are *rejected* with `TOO_MANY_PARTS` |
| `max_avg_part_size_for_too_many_parts` | **10 GiB** ⚠ | **1 GiB** | The delay/throw checks are **disabled** once average part size in the partition exceeds this — big well-merged parts never trip the limit |
| `max_parts_in_total` | **100000** | **100000** | Global active-part cap across all partitions |
| `inactive_parts_to_delay_insert` / `inactive_parts_to_throw_insert` | **0** (off) | same | Same idea for inactive (pre-GC) parts |
| `max_delay_to_insert` | **1 s** | same | Upper bound on the artificial insert delay |
| `min_delay_to_insert_ms` | **10 ms** | same | Lower bound on the artificial insert delay |

**The delay ramps** from `min_delay_to_insert_ms` up to `max_delay_to_insert` as the part
count climbs from `parts_to_delay_insert` toward `parts_to_throw_insert`
(`MergeTreeData.cpp` `delayInsertOrThrowIfNeeded`).

⚠ **Net effect of the divergence:** Proton starts delaying at **150** and throwing at
**300**, vs upstream's **1000 / 3000**. Combined with Proton's higher
`max_avg_part_size_for_too_many_parts` (10 GiB — keeps the check *active* for larger parts),
Proton is **far more eager** to delay/reject inserts. On insert-heavy or many-small-parts
workloads you will hit `TOO_MANY_PARTS` on Proton where stock ClickHouse would not.

---

## 6. Merge scheduling cadence & cleanup

| Setting | Proton | Upstream | Meaning |
|---|---|---|---|
| `merge_selecting_sleep_ms` | **5000** | **5000** | Base sleep between merge-selection attempts when nothing was selected |
| `max_merge_selecting_sleep_ms` | **60000** | **60000** | Upper bound on that backoff |
| `merge_selecting_sleep_slowdown_factor` | **1.2** | same | Backoff multiplier when idle, divided when a merge is assigned |
| `old_parts_lifetime` | **480 s** (8 min) | **480 s** | How long obsolete (merged-away) parts linger before GC |
| `temporary_directories_lifetime` | **86400 s** | same | Lifetime of `tmp_` merge/mutation dirs — **don't lower**, long merges need it |
| `merge_tree_clear_old_parts_interval_seconds` | **1** | same | Period of the old-part cleanup task |
| `merge_tree_clear_old_temporary_directories_interval_seconds` | **60** | same | Period of the tmp-dir cleanup task |
| `merge_tree_clear_old_broken_detached_parts_ttl_timeout_seconds` | **2592000** (30 d) | same | When to GC old broken detached parts |
| `min_age_to_force_merge_seconds` | **0** (off) | **0** | If every part in a range is older than this, *always* eligible to merge — forces eventual compaction of cold ranges |
| `min_age_to_force_merge_on_partition_only` | **false** | same | Apply the above only to whole partitions |

Lowering `merge_selecting_sleep_ms` makes the engine notice mergeable parts sooner, at the
cost of more frequent selection passes (and, in replicated/clustered setups, more
ZooKeeper/metadata traffic). The slowdown factor means an idle table backs off toward 60 s.

---

## 7. Proton vs. upstream divergences (summary)

The settings where Proton ≠ current ClickHouse — these are what to watch when porting or
diagnosing:

| Setting | Proton | Upstream | Impact |
|---|---|---|---|
| `parts_to_delay_insert` | **150** | 1000 | Proton delays inserts ~6.7× sooner |
| `parts_to_throw_insert` | **300** | 3000 | Proton rejects inserts 10× sooner |
| `max_avg_part_size_for_too_many_parts` | **10 GiB** | 1 GiB | Proton keeps the throttle active for larger parts (stricter) |
| `max_replicated_merges_in_queue` | **16** | 1000 | Far smaller replicated merge queue |
| `background_fetches_pool_size` | **8** | 16 | Half the replica-fetch parallelism |
| `background_schedule_pool_size` | **16** | 512 | Much smaller periodic-task pool (matters at cluster scale) |
| `merge_selector_algorithm` / `merge_selector_base` | *absent* | present | Proton predates the configurable selector; uses the legacy Simple selector |

Everything else surveyed (pool size 16, ratio 2, 150 GiB max merge, vertical-merge
thresholds, TTL timeouts, `old_parts_lifetime`, cadence settings) is **identical** to
upstream.

---

## 8. Tuning playbook

### "Too many parts" on insert-heavy ingestion
1. **First, fix the cause, not the symptom.** The error means merges are behind. Check
   `background_pool_size` vs core/IO headroom; check that your `PARTITION BY` isn't too
   granular (each partition merges independently — over-partitioning multiplies part count).
2. If merges genuinely keep up but the limit is just *low for your workload*, raise toward
   upstream values per-table:
   ```sql
   ALTER STREAM t MODIFY SETTING parts_to_delay_insert = 1000, parts_to_throw_insert = 3000;
   ```
   This trades higher peak part counts (slower `SELECT`) for fewer insert rejections.
3. Batch inserts larger / less frequently — the single most effective lever. Fewer, bigger
   inserts = fewer initial parts = less merge pressure.

### Merges starving / huge merges hogging the pool
- Keep `number_of_free_entries_in_pool_to_lower_max_size_of_merge` at 8 (default) so small
  merges keep flowing under load.
- Consider `background_merges_mutations_scheduling_policy = shortest_task_first` for
  throughput, **but** it can starve large merges — only on append-heavy, latency-tolerant
  tables.

### S3 / tiered storage (ties into the storage-policy work)
- Tiering moves use the **move pool** (`background_move_pool_size`, default 8) + **MOVE
  TTL**, not the merge pool.
- Set `prefer_not_to_merge: true` on the S3 volume so parts aren't re-merged on object
  storage (avoids read-modify-write amplification).
- Let merges **finish on the hot tier before the move** — drive tiering by age via MOVE
  TTL, keep `move_factor` at the default `0.1`, so only a few large parts ever land on S3.
- `max_merge_delayed_streams_for_parallel_write` (40) bounds memory during the rare vertical
  merge to S3 — lower it for very wide schemas on memory-constrained nodes.
- Use `ttl_only_drop_parts = true` + time partitioning so expiry is a cheap part drop.

### CPU/IO control for merges
- `min_merge_bytes_to_use_direct_io` (10 GiB) keeps large merges from polluting the page
  cache; lower it if huge merges evict hot query data, raise/disable (0) if the box has
  plenty of RAM and you want merges cached.

---

## 9. How to set these

- **Pool sizes (`ServerSettings`)** — server config, restart required:
  ```xml
  <clickhouse>
      <background_pool_size>32</background_pool_size>
      <background_merges_mutations_concurrency_ratio>2</background_merges_mutations_concurrency_ratio>
  </clickhouse>
  ```
- **Merge behavior (`MergeTreeSettings`)** — per-table at creation:
  ```sql
  CREATE STREAM t (...) SETTINGS parts_to_throw_insert = 3000, max_parts_to_merge_at_once = 100;
  ```
  or live:
  ```sql
  ALTER STREAM t MODIFY SETTING parts_to_throw_insert = 3000;
  ```
  or globally for all MergeTree tables via the `<merge_tree>` config section:
  ```xml
  <merge_tree>
      <parts_to_throw_insert>3000</parts_to_throw_insert>
      <max_bytes_to_merge_at_max_space_in_pool>161061273600</max_bytes_to_merge_at_max_space_in_pool>
  </merge_tree>
  ```

---

## 10. Observability

| What | Where |
|---|---|
| In-flight merges (progress, bytes, memory) | `system.merges` |
| Background pool occupancy | `system.metrics` (`BackgroundMergesAndMutationsPoolTask`, `BackgroundMergesAndMutationsPoolSize`), `system.asynchronous_metrics` |
| Per-partition part counts | `system.parts` (`GROUP BY table, partition`), `system.parts_columns` |
| Completed merge history & timings | `system.part_log` (enable `<part_log>`) |
| Merge-selection / "too many parts" events | `system.events` (`RejectedInserts`, `DelayedInserts`, `Merge`) |

Quick health check:
```sql
SELECT database, table, partition, count() AS parts, formatReadableSize(sum(bytes_on_disk)) AS size
FROM system.parts WHERE active GROUP BY 1,2,3 ORDER BY parts DESC LIMIT 20;
```

---

## 11. Source references

| Setting group | Proton | Upstream ClickHouse |
|---|---|---|
| Background pools | `src/Core/ServerSettings.h:78-87` | `src/Core/ServerSettings.cpp:859-910` |
| Merge sizing | `src/Storages/MergeTree/MergeTreeSettings.h:48-57` | `src/Storages/MergeTree/MergeTreeSettings.cpp:465-542` |
| Insert throttling | `src/Storages/MergeTree/MergeTreeSettings.h:83-90` | `src/Storages/MergeTree/MergeTreeSettings.cpp:855-954` |
| TTL merges | `src/Storages/MergeTree/MergeTreeSettings.h:143-145, 57` | `src/Storages/MergeTree/MergeTreeSettings.cpp:542` |
| Throttle enforcement logic | `src/Storages/MergeTree/MergeTreeData.cpp:4172-4244` (`delayInsertOrThrowIfNeeded`) | same path |
| Move trigger (`move_factor`) | `src/Storages/MergeTree/MergeTreePartsMover.cpp:114` | same path |
