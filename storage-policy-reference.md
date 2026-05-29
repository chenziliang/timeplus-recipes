# Proton-Enterprise Storage Configuration Reference

This document enumerates every configurable parameter for **Storage Policies**, **Volumes**, and **Disks** reachable via DDL (`CREATE STORAGE POLICY`, `CREATE DISK`), including default values, accepted ranges, and concrete Timeplus syntax examples.

Reflects the state of the repo after the `prefer_not_to_merge` / `volume_priority` / `least_used_ttl_ms` / `perform_ttl_move_on_insert` / `max_data_part_size_*` fixes (schema v2).

---

## Table of Contents

1. [Syntax overview](#1-syntax-overview)
2. [Storage policy parameters](#2-storage-policy-parameters)
3. [Volume parameters](#3-volume-parameters)
4. [Disk parameters by type](#4-disk-parameters-by-type)
   - [`local`](#41-local)
   - [`encrypted`](#42-encrypted)
   - [`cache`](#43-cache)
   - [`s3` / `s3_plain` / `s3_plain_rewritable`](#44-s3--s3_plain--s3_plain_rewritable)
   - [`local_blob_storage`](#45-local_blob_storage)
   - [`web`](#46-web)
   - [`azure_blob_storage`](#47-azure_blob_storage)
5. [Complete end-to-end examples](#5-complete-end-to-end-examples)
6. [Verification queries](#6-verification-queries)

---

## 1. Syntax overview

### `CREATE DISK`

```sql
CREATE DISK <disk_name> disk(
    type = '<type>',
    key1 = value1,
    key2 = 'value2',
    ...
);
```

Optional: a **named collection** can hold shared credentials and be referenced from multiple `CREATE DISK` statements:

```sql
CREATE NAMED COLLECTION s3_creds AS
    access_key_id = 'minioadmin',
    secret_access_key = 'minioadmin';

CREATE DISK my_s3 disk(
    named_collection = s3_creds,
    type = 's3',
    endpoint = 'https://s3.us-east-1.amazonaws.com/my-bucket/path/'
);
```

### `CREATE STORAGE POLICY`

```sql
CREATE STORAGE POLICY <policy_name> AS $$
volumes:
  <volume_name>:
    disk: <disk_name>
    <volume_key>: <value>
  <volume_name_2>:
    disk: <disk_name_2>
    ...
move_factor: <0..1>
$$;
```

**YAML formatting gotchas in `$$ ... $$`:** trailing whitespace on key lines (e.g. `volumes:  `) and leading blank lines can cause the YAML→XML parser to mis-emit sibling scalars as XML attributes instead of children, producing `Volume must contain at least one disk` even when `disk:` is specified. Use clean 2-space indent, no trailing whitespace, no surrounding blank lines.

---

## 2. Storage policy parameters

Configuration path: top level of the YAML body.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `volumes` | mapping | **required** | Mapping of volume name → volume config. At least one volume is required. The map's natural iteration order is the volume order unless `volume_priority` is set (see §3). |
| `move_factor` | double in `[0.0, 1.0]` | `0.1` if >1 volume, else `0.0` | Background mover threshold. When a volume's used space exceeds `(total_size × move_factor)`, the mover relocates oldest parts to the next volume in the policy. Set to `0` to disable. |

**Source:** `src/Disks/StorageHelpers.cpp:139`, `src/Disks/StoragePolicy.cpp:80-86`.

---

## 4. Volume parameters

Configuration path: under each named volume in `volumes:`.

| Parameter | Type | Default | Description | Schema |
|---|---|---|---|---|
| `disk` | string | **required** (at least one) | Name of a disk declared via `CREATE DISK` (or in static XML config). Multiple `disk:` entries → JBOD volume (round-robin or least-used across the disks). | v1 |
| `load_balancing` | enum: `round_robin`, `least_used` | `round_robin` | Disk selection algorithm within a multi-disk volume. `least_used` picks the disk with the most free space (cached — see `least_used_ttl_ms`). | v1 |
| `max_data_part_size_bytes` | uint64 | `0` (unlimited) | Hard cap on individual data-part size on this volume. Parts larger than this go to the next volume. Mutually exclusive with `max_data_part_size_ratio`. | v1 |
| `max_data_part_size_ratio` | double | `0.0` (disabled) | Same as above but computed as `ratio × (sum of disk sizes / disk count)` at startup. Use when disk sizes vary or change over time. | v1 |
| `perform_ttl_move_on_insert` | bool | `true` | When `true`, parts that already match a TTL move rule on insert are moved synchronously during write. When `false`, the insert lands on the current volume and the mover relocates later. Set `false` for high-throughput ingest to keep the insert path fast. | v1 |
| `volume_priority` | uint64 | `UINT64_MAX` (unset) | Explicit ordering. When set, every volume in the policy must have a unique value covering `1..N` without gaps. Lower = higher priority (tried first). `0` is treated as "unset" for backwards-compat with pre-fix metastore data. | v1 (rewired) |
| `prefer_not_to_merge` | bool | `false` | When `true`, the background merger skips parts on this volume. Use on cold/object-store tiers where merges burn S3/Azure GET+PUT cost and wall time. Has no effect on TTL-driven moves *into* the volume — only on consolidation *within* the volume. | **v2** |
| `least_used_ttl_ms` | uint64 (ms) | `60000` (60 s) | Refresh interval for the `least_used` disk-size cache. `0` disables caching (recompute on every reserve). Lower when disk usage changes rapidly from outside the cluster; higher for cheaper steady-state. | **v2** |

**Source:**
- DDL parser: `src/Disks/StorageHelpers.cpp:152-176` (`check_and_create_volume` lambda)
- Legacy XML (and the runtime VolumeJBOD that consumes the descriptor's emitted XML): `src/Disks/VolumeJBOD.cpp:16-75`, `src/Disks/IVolume.cpp:28-50`
- Uniqueness/range enforcement: `src/Disks/StoragePolicy.cpp:60-90`

### Volume-only example

```sql
CREATE STORAGE POLICY mixed_volume AS $$
volumes:
  hot:
    disk: nvme0
    volume_priority: 1
    max_data_part_size_bytes: 53687091200   -- 50 GB cap, larger parts spill to warm
  warm:
    disk: hdd_1
    disk2: hdd_2                            -- JBOD: two disks in one volume
    load_balancing: least_used
    least_used_ttl_ms: 30000
    volume_priority: 2
  cold:
    disk: s3_archive
    prefer_not_to_merge: true               -- skip merges on S3
    perform_ttl_move_on_insert: false       -- background move only
    volume_priority: 3
move_factor: 0.2
$$;
```

Note the JBOD pattern on `warm`: the parser collects every child key whose name starts with `disk` (`disk`, `disk2`, `disk3`, ...) into a list, so all of `disk: hdd_1` / `disk_two: hdd_2` / `disk99: hdd_3` work.

---

## 4. Disk parameters by type

Configuration path: inside `disk(...)` of `CREATE DISK`. All disk types accept these **common** keys:

| Parameter | Type | Default | Description |
|---|---|---|---|
| `type` | string | **required** | Disk type discriminator (see subsections below). |
| `named_collection` | string | none | Pulls additional `key=value` settings from a previously-defined `NAMED COLLECTION`. |
| `skip_access_check` | bool | `false` | Skip the startup write-probe. Useful when access permissions can't be verified at boot (e.g. read-only mirrors). |
| `metadata_type` | enum: `local`, `plain`, `plain_rewritable`, `web` | `local` for `s3`; required for `local_blob_storage` with `plain` metadata | Where disk metadata (object key → file mapping) lives. `local` = local fs metadata + remote data; `plain` = no rename/hardlink, metadata derived from object keys; `web` = read-only from static HTTP. |

### 4.1 `local`

Local filesystem disk. The simplest type — a directory on the host.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `type` | string | **`'local'`** | Disk type. |
| `path` | string | required (unless `name='default'`) | Filesystem path. **Must end with `/`**. Must not equal the global server `<path>` (use the `default` disk for that). |
| `keep_free_space_bytes` | uint64 | `0` | Reserve N bytes — reservations will fail when free space would drop below this. Mutually exclusive with `keep_free_space_ratio`. |
| `keep_free_space_ratio` | double `[0, 1]` | unset | Reserve a fraction of total disk size. Computed at startup. |
| `skip_access_check` | bool | `false` | See common. |

**Source:** `src/Disks/loadLocalDiskConfig.cpp:16-61`, `src/Disks/DiskLocal.cpp:752`.

```sql
CREATE DISK local_data disk(
    type = 'local',
    path = '/var/lib/timeplusd/extra/',
    keep_free_space_ratio = 0.1
);
```

### 4.2 `encrypted`

A wrapper that encrypts a delegate disk with AES-CTR.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `type` | string | **`'encrypted'`** | Disk type. |
| `disk` | string | **required** | Name of the underlying disk (must already exist). |
| `path` | string | `''` | Sub-path on the wrapped disk where encrypted data lives. Must end with `/` if set. |
| `algorithm` | enum: `aes_128_ctr`, `aes_192_ctr`, `aes_256_ctr` | `aes_128_ctr` | AES variant. |
| `key` | string | one of `key`/`key_hex` required | Raw key bytes. Length must match algorithm (16/24/32 bytes). |
| `key_hex` | hex string | — | Hex-encoded key. Length must match algorithm (32/48/64 hex chars). |
| `key[@id]` / `key_hex[@id]` | uint64 | none | Numeric key ID for multi-key rotation. Multiple `key` blocks can coexist as long as IDs are unique. |
| `current_key` | string | first key if only one | Designates which key encrypts *new* writes (others remain available for decryption). |
| `current_key_hex` | hex | — | Hex variant of above. |
| `current_key_id` | uint64 | — | Pick current key by its `@id`. |
| `use_fake_transaction` | bool | `true` | Disables real transaction semantics on the wrapped disk's transactions. Set `false` for stricter atomicity on disks that support it. |

**Source:** `src/Disks/DiskEncrypted.cpp:40-258` (key parsing), `:301` (use_fake_transaction).

```sql
CREATE DISK local_encrypted disk(
    type = 'encrypted',
    disk = 'local_data',
    path = 'encrypted/',
    algorithm = 'aes_256_ctr',
    key_hex = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff',
    use_fake_transaction = 1
);
```

### 4.3 `cache`

A read-write filesystem cache layered on top of a slower delegate disk (typically an object-store disk).

| Parameter | Type | Default | Description |
|---|---|---|---|
| `type` | string | **`'cache'`** | Disk type. |
| `disk` | string | **required** | Underlying disk to cache. |
| `path` | string | **required** | Local directory holding cached segments. |
| `max_size` | size (with `K`/`M`/`G`/`T` suffix or bytes) | **required** (non-zero) | Total cache size on local disk. |
| `max_elements` | uint64 | implementation default (`FILECACHE_DEFAULT_MAX_ELEMENTS`) | Max number of cached file segments. |
| `max_file_segment_size` | size | implementation default (`FILECACHE_DEFAULT_MAX_FILE_SEGMENT_SIZE`) | Max bytes per cached segment. Files larger than this are split. |
| `cache_on_write_operations` | bool | `false` | When `true`, writes through the cache (writeback). When `false`, writes go straight to the delegate disk and only reads are cached. |
| `enable_filesystem_query_cache_limit` | bool | `false` | Enforce a per-query bytes-read-from-cache cap (set via the `max_query_cache_size` query setting). |
| `cache_hits_threshold` | uint64 | implementation default (`FILECACHE_DEFAULT_HITS_THRESHOLD`) | Don't cache a segment until it has been read this many times. `0` = cache on first miss. |
| `enable_bypass_cache_with_threashold` *(sic, typo preserved in code)* | bool | `false` | When `true`, large reads above `bypass_cache_threashold` skip the cache entirely. |
| `bypass_cache_threashold` *(sic)* | size | `FILECACHE_BYPASS_THRESHOLD` | Size threshold for the above bypass. |
| `boundary_alignment` | size | `DBMS_DEFAULT_BUFFER_SIZE` | Cached segments are aligned to multiples of this size — improves locality of reuse. |
| `delayed_cleanup_interval_ms` | uint64 (ms) | `FILECACHE_DELAYED_CLEANUP_INTERVAL_MS` | How often the background cleaner reclaims deleted segments. |

**Source:** `src/Interpreters/Cache/FileCacheSettings.cpp`.

```sql
CREATE DISK s3_with_cache disk(
    type = 'cache',
    disk = 's3_cold',
    path = '/var/lib/timeplusd/cache/s3_cold/',
    max_size = '100Gi',
    max_file_segment_size = 67108864,         -- 64 MiB
    cache_on_write_operations = 0,
    boundary_alignment = 1048576,              -- 1 MiB
    cache_hits_threshold = 0
);
```

### 4.4 `s3` / `s3_plain` / `s3_plain_rewritable`

- **`s3`** — full read-write S3-backed disk with local metadata (supports rename / hardlink).
- **`s3_plain`** — read-mostly S3 disk, no local metadata. Cannot rename, no hardlinks. Lower overhead.
- **`s3_plain_rewritable`** — middle ground: rewritable but still no rename/hardlink.

All three share the same config keys.

#### S3 connection / auth keys

| Parameter | Type | Default | Description |
|---|---|---|---|
| `type` | string | **`'s3'` / `'s3_plain'` / `'s3_plain_rewritable'`** | Disk type. |
| `endpoint` | URL | **required** | Full S3 URL incl. bucket and key prefix. Must end with `/`. Example: `https://s3.us-east-1.amazonaws.com/my-bucket/proton-data/`. |
| `region` | string | `''` | AWS region. Required for S3 Express directory buckets. |
| `access_key_id` | string | `''` | Static credentials. Leave blank when using env/IMDS/IAM-role auth. |
| `secret_access_key` | string | `''` | Static credentials. |
| `use_environment_credentials` | bool | `false` (per-disk; falls back to global `s3.use_environment_credentials`) | Use the AWS SDK credentials chain (env vars, EC2/EKS role, etc.). |
| `use_insecure_imds_request` | bool | `false` | Allow the AWS SDK to use IMDSv1. Set `true` only when on legacy infra without IMDSv2. |
| `expiration_window_seconds` | uint64 | `S3::DEFAULT_EXPIRATION_WINDOW_SECONDS` (120) | Refresh temporary credentials this many seconds before they expire. |
| `no_sign_request` | bool | `false` | Issue unsigned requests (anonymous public bucket access). |
| `server_side_encryption_customer_key_base64` | base64 string | `''` | SSE-C customer key. Triggers SSE-C encryption on PUT/GET. |

#### S3 client / network keys

| Parameter | Type | Default | Description |
|---|---|---|---|
| `connect_timeout_ms` | uint | `10000` | TCP connect timeout. |
| `request_timeout_ms` | uint | `30000` | Per-request timeout. |
| `max_connections` | uint | `100` | Max concurrent HTTP connections in the pool. |
| `http_keep_alive_timeout` | uint | `5` | Keep-alive timeout in seconds. |
| `http_keep_alive_max_requests` | uint | `100` | Max requests per kept-alive connection before forced rotation. |
| `use_adaptive_timeouts` | bool | client default | Let the AWS SDK adjust timeouts based on observed latency. |
| `retry_attempts` | uint64 | follows global `s3_retry_attempts` | Max retries for retryable S3 errors. |

#### S3 object-storage tuning keys

| Parameter | Type | Default | Description |
|---|---|---|---|
| `min_bytes_for_seek` | uint64 | `1048576` (1 MiB) | Reads smaller than this gap don't trigger a re-issue (the existing stream is read through). Tune to local network latency. |
| `list_object_keys_size` | int | `1000` | Page size for ListObjectsV2. |
| `objects_chunk_size_to_delete` | int | `1000` | Batch size for DeleteObjects. Hard-capped at 1000 by AWS. |

#### S3 upload tuning keys (multipart)

All under the `s3_` prefix on the disk:

| Parameter | Type | Default | Description |
|---|---|---|---|
| `s3_storage_class` | string | `''` (AWS default: `STANDARD`) | E.g. `STANDARD_IA`, `INTELLIGENT_TIERING`, `GLACIER_IR`. |
| `strict_upload_part_size` | uint64 | global setting | When non-zero, every multipart part is exactly this size (last part is shorter). |
| `min_upload_part_size` | uint64 | global setting | Lower bound for adaptive part sizing (default ~5 MiB). |
| `max_upload_part_size` | uint64 | global setting | Upper bound (AWS hard max: 5 GiB). |
| `upload_part_size_multiply_factor` | uint64 | global setting | Adaptive growth rate per `upload_part_size_multiply_parts_count_threshold` parts uploaded. |
| `upload_part_size_multiply_parts_count_threshold` | uint64 | global setting | See above. |
| `max_inflight_parts_for_one_file` | uint64 | global setting | Concurrent in-flight part uploads per file. |
| `max_part_number` | uint64 | `10000` (AWS hard limit) | Refuse to start an upload that would need more than this. |
| `max_single_part_upload_size` | uint64 | global setting | Threshold below which to use single-PUT instead of multipart. |
| `max_single_operation_copy_size` | uint64 | global setting | Threshold for `CopyObject` vs UploadPartCopy. |
| `max_single_read_retries` | uint64 | global setting | Retries on a single GET/range read. |
| `check_objects_after_upload` | bool | global setting | HEAD-after-PUT to verify upload landed. Costs an extra request. |
| `max_get_rps` / `max_get_burst` | uint64 | global setting | Client-side GET-rate throttle. |
| `max_put_rps` / `max_put_burst` | uint64 | global setting | Client-side PUT-rate throttle. |

#### Other

| Parameter | Type | Default | Description |
|---|---|---|---|
| `skip_access_check` | bool | `false` | Skip the boot-time write probe. |
| `metadata_type` | enum | `'local'` | See common. |

**Source:** `src/Disks/ObjectStorages/S3/diskSettings.cpp`, `src/Storages/StorageS3Settings.cpp:44-229`.

```sql
CREATE DISK s3_cold disk(
    type = 's3',
    endpoint = 'https://s3.us-east-1.amazonaws.com/proton-cold-tier/data/',
    region = 'us-east-1',
    use_environment_credentials = 1,           -- IRSA / EC2 role
    s3_storage_class = 'STANDARD_IA',
    request_timeout_ms = 60000,
    max_single_read_retries = 5,
    min_bytes_for_seek = 4194304,              -- 4 MiB
    check_objects_after_upload = 0
);
```

For S3-compatible stores (MinIO, Wasabi, GCS HMAC), use static keys via a named collection:

```sql
CREATE NAMED COLLECTION minio_creds AS
    access_key_id = 'minioadmin',
    secret_access_key = 'minioadmin';

CREATE DISK minio disk(
    named_collection = minio_creds,
    type = 's3',
    endpoint = 'http://minio:9000/proton/data/'
);
```

### 4.5 `local_blob_storage`

Local-filesystem disk that emulates the object-storage interface (used to test cache/encrypted layers locally without a real S3).

| Parameter | Type | Default | Description |
|---|---|---|---|
| `type` | string | **`'local_blob_storage'`** (or `'local'` via this code path) | Disk type. |
| `path` | string | **required** | Local directory acting as the "bucket". Must end with `/`. |
| `keep_free_space_bytes` / `keep_free_space_ratio` | same as `local` | same as `local` | See §4.1. |
| `metadata_type` | enum | `'local'` | `'plain'` to emulate `s3_plain`-style metadata. |

**Source:** `src/Disks/ObjectStorages/ObjectStorageFactory.cpp:280-299`.

```sql
CREATE DISK local_emulated_s3 disk(
    type = 'local_blob_storage',
    path = '/var/lib/timeplusd/local-shared/'
);

CREATE DISK local_plain_shared disk(
    type = 'local_blob_storage',
    metadata_type = 'plain',
    path = '/var/lib/timeplusd/local-plain/'
);
```

### 4.6 `web`

Read-only disk pulling static files over HTTP(S). Used for distributing pre-built parts to read replicas.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `type` | string | **`'web'`** | Disk type. |
| `endpoint` | URL | **required** | Root URL. Must end with `/`. |

**Source:** `src/Disks/ObjectStorages/ObjectStorageFactory.cpp:253-278`.

```sql
CREATE DISK distribute_ro disk(
    type = 'web',
    endpoint = 'https://artifacts.internal/proton-mirror/'
);
```

### 4.7 `azure_blob_storage`

Microsoft Azure Blob Storage backend. Available when the build has `USE_AZURE_BLOB_STORAGE=ON`.

#### Auth / connection

| Parameter | Type | Default | Description |
|---|---|---|---|
| `type` | string | **`'azure_blob_storage'`** | Disk type. |
| `endpoint` | URL | one of `endpoint` / `connection_string` / `storage_account_url` | Full blob URL including container & key prefix. |
| `endpoint_contains_account_name` | bool | `true` | Whether the URL embeds the account name. |
| `connection_string` | string | — | Azure connection-string auth. |
| `storage_account_url` | URL | — | Account URL when using shared key. |
| `container_name` | string | required (with `connection_string` / `storage_account_url`) | Blob container name. |
| `account_name` | string | required (with `storage_account_url`) | Shared-key account name. |
| `account_key` | string | required (with `storage_account_url`) | Shared-key secret. |
| `container_already_exists` | bool | — | When `true`, skip the container-create check. When `false`, force-create. When unset, attempt create-if-missing. |

#### Tuning

| Parameter | Type | Default | Description |
|---|---|---|---|
| `min_bytes_for_seek` | uint64 | `1048576` (1 MiB) | Same role as S3's. |
| `max_single_part_upload_size` | uint64 | global `azure_max_single_part_upload_size` | Single-PUT cutoff. |
| `min_upload_part_size` / `max_upload_part_size` | uint64 | global `azure_min/max_upload_part_size` | Multipart part sizing. |
| `max_single_part_copy_size` | uint64 | global `azure_max_single_part_copy_size` | Single CopyBlob vs server-side multi-part copy cutoff. |
| `use_native_copy` | bool | `false` | Use the Azure server-side copy API instead of client-mediated streaming. |
| `max_unexpected_write_error_retries` | uint64 | global | Retry budget on unexpected upload errors. |
| `max_inflight_parts_for_one_file` | uint64 | global | Concurrent uploads. |
| `strict_upload_part_size` | uint64 | global | When set, fixed part size. |
| `upload_part_size_multiply_factor` / `upload_part_size_multiply_parts_count_threshold` | uint64 | global | Adaptive growth. |

**Source:** `src/Disks/ObjectStorages/AzureBlobStorage/AzureBlobStorageAuth.cpp:60-233`.

```sql
CREATE DISK azure_cold disk(
    type = 'azure_blob_storage',
    storage_account_url = 'https://protonstore.blob.core.windows.net',
    container_name = 'proton-cold',
    account_name = 'protonstore',
    account_key = 'BASE64KEY==',
    min_bytes_for_seek = 4194304,
    use_native_copy = 1
);
```

---

## 5. Complete end-to-end examples

### 5.1 Three-tier `gp3 → st1 → S3` policy

```sql
-- ============ DISK DECLARATIONS ============

-- Tier 1: the default local disk on the proton-data PV (no CREATE DISK needed for 'default')

-- Tier 2: a second local disk on the warm PV
CREATE DISK warm_disk disk(
    type = 'local',
    path = '/var/lib/timeplusd/warm/'
);

-- Tier 3: S3 cold tier with IRSA credentials
CREATE DISK s3_cold disk(
    type = 's3',
    endpoint = 'https://s3.us-east-1.amazonaws.com/proton-cold-tier/data/',
    region = 'us-east-1',
    use_environment_credentials = 1,
    s3_storage_class = 'STANDARD_IA',
    request_timeout_ms = 60000
);

-- ============ STORAGE POLICY ============

CREATE STORAGE POLICY tiered_3 AS $$
volumes:
  hot:
    disk: default
    volume_priority: 1
  warm:
    disk: warm_disk
    volume_priority: 2
    perform_ttl_move_on_insert: false
  cold:
    disk: s3_cold
    volume_priority: 3
    prefer_not_to_merge: true
move_factor: 0.2
$$;

-- ============ STREAM USING THE POLICY ============

CREATE STREAM events (
    event_time DateTime,
    user_id UInt64,
    payload String
)
PARTITION BY toDate(event_time)
ORDER BY (event_time, user_id)
TTL
    event_time + INTERVAL 3 DAY TO VOLUME 'warm',
    event_time + INTERVAL 7 DAY TO VOLUME 'cold',
    event_time + INTERVAL 90 DAY DELETE
SETTINGS storage_policy = 'tiered_3', ttl_only_drop_parts = 1;
```

### 5.2 Two-tier with JBOD warm + S3 cold + cache

```sql
-- Two HDD JBOD volumes
CREATE DISK hdd_1 disk(type = 'local', path = '/mnt/hdd1/timeplus/');
CREATE DISK hdd_2 disk(type = 'local', path = '/mnt/hdd2/timeplus/');

-- S3 with a read cache in front of it
CREATE NAMED COLLECTION s3_creds AS
    access_key_id = 'minioadmin',
    secret_access_key = 'minioadmin';

CREATE DISK s3_raw disk(
    named_collection = s3_creds,
    type = 's3',
    endpoint = 'http://minio:9000/proton/cold/'
);

CREATE DISK s3_cached disk(
    type = 'cache',
    disk = 's3_raw',
    path = '/var/lib/timeplusd/cache/s3/',
    max_size = '50Gi',
    max_file_segment_size = 67108864,
    cache_on_write_operations = 0,
    boundary_alignment = 1048576
);

CREATE STORAGE POLICY jbod_s3 AS $$
volumes:
  warm:
    disk: hdd_1
    disk2: hdd_2
    load_balancing: least_used
    least_used_ttl_ms: 30000
  cold:
    disk: s3_cached
    prefer_not_to_merge: true
move_factor: 0.3
$$;
```

### 5.3 Single-volume policy with explicit limits

```sql
CREATE STORAGE POLICY bounded_default AS $$
volumes:
  main:
    disk: default
    max_data_part_size_bytes: 10737418240   -- refuse parts > 10 GB
$$;
```

(No `move_factor` needed — defaults to `0.0` for single-volume policies.)

### 5.4 Encrypted local disk

```sql
CREATE DISK local_data disk(
    type = 'local',
    path = '/var/lib/timeplusd/data/'
);

CREATE DISK local_encrypted disk(
    type = 'encrypted',
    disk = 'local_data',
    path = 'encrypted/',
    algorithm = 'aes_256_ctr',
    key_hex = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff'
);

CREATE STORAGE POLICY enc AS $$
volumes:
  enc:
    disk: local_encrypted
$$;
```

---

## 6. Verification queries

### Inspect the disks the server actually loaded

```sql
SELECT name, type, path, is_encrypted, is_read_only, total_space, free_space
FROM system.disks
ORDER BY name;
```

### Inspect a storage policy's volumes and effective settings

```sql
SELECT
    policy_name,
    volume_name,
    volume_priority,
    disks,
    max_data_part_size,
    move_factor,
    prefer_not_to_merge,
    perform_ttl_move_on_insert,
    least_used_ttl_ms,
    load_balancing
FROM system.storage_policies
WHERE policy_name = 'tiered_3'
ORDER BY volume_priority;
```

Expected: `prefer_not_to_merge = 1` on `cold`, `perform_ttl_move_on_insert = 0` on `warm`, `volume_priority` matches what you declared.

### Inspect part distribution across tiers

```sql
SELECT
    table,
    disk_name,
    count() AS parts,
    formatReadableSize(sum(bytes_on_disk)) AS size
FROM system.parts
WHERE active AND database = currentDatabase() AND table = 'events'
GROUP BY table, disk_name
ORDER BY table, disk_name;
```

After TTL moves run, parts older than 3 days should appear under the `warm_disk`, older than 7 under `s3_cold`.
