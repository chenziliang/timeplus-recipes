# timeplusd client examples

`timeplusd client` is the native CLI for Timeplus Enterprise. It is similar to
`clickhouse-client` and shares most of its flags. The binary ships in the
`timeplus/bin` folder of the bare-metal package and is on `PATH` inside the
`timeplus/timeplusd` Docker image.

```
timeplusd client [OPTIONS] [-q "SQL"]
```

Common connection flags:

| Flag | Default | Purpose |
| --- | --- | --- |
| `--host, -h` | `localhost` | Server hostname |
| `--port` | `8463` | TCP port |
| `--user, -u` | `default` | User name |
| `--password` | *(empty)* | Password (or use `--ask-password`) |
| `--database, -d` | `default` | Default database |
| `--secure` | off | TLS connection |
| `--format, -f` | `PrettyCompact` | Output format |

---

## 1. Execute SQL statements

### 1.1 Interactive shell

```bash
timeplusd client --host 127.0.0.1 --port 8463 -u default --ask-password
```

Exit with `Ctrl+D`, `exit`, `quit`, or `:q`.

### 1.2 One-shot query (batch mode)

```bash
timeplusd client -q "SELECT version()"
timeplusd client -d mydb -q "SELECT count() FROM events"
```

### 1.3 Multiple statements

Use `--multiquery` / `-n` (works for every statement except `INSERT`):

```bash
timeplusd client -n -q "
  CREATE STREAM IF NOT EXISTS demo(id int, msg string);
  SELECT count() FROM demo;
"
```

### 1.4 Run a script file

```bash
# via stdin
timeplusd client --multiquery < statements.sql

# via --queries-file
timeplusd client --queries-file ./statements.sql
```

### 1.5 Parameterized queries

Server-side substitution avoids client-side string formatting:

```bash
timeplusd client \
  --param_ids="[1, 2, 3]" \
  -q "SELECT * FROM sensors WHERE id IN {ids:array(uint32)}"
```

Identifiers can be parameterized too:

```bash
timeplusd client \
  --param_db=default --param_tbl=sensors --param_col=id \
  -q "SELECT {col:identifier} FROM {db:identifier}.{tbl:identifier} LIMIT 10"
```

### 1.6 Useful diagnostic flags

```bash
timeplusd client --time  -q "SELECT count() FROM big_stream"   # print elapsed time
timeplusd client --stacktrace -q "SELECT bad_fn()"             # include server stack trace
timeplusd client --progress   -q "SELECT ..."                  # show rows/sec progress
```

---

## 2. Load data into timeplusd

`INSERT` accepts the same formats as ClickHouse. Send the payload on `stdin`
and declare the format in the `INSERT` statement.

Example target stream used below:

```sql
CREATE STREAM events (
  id       uint64,
  name     string,
  ts       datetime64(3)
);
```

### 2.1 CSV

```bash
cat <<EOF | timeplusd client -q "INSERT INTO events FORMAT CSV"
1,alice,2026-04-20 10:00:00.000
2,bob,2026-04-20 10:00:01.000
EOF
```

### 2.2 CSV with header row

```bash
timeplusd client -q "INSERT INTO events FORMAT CSVWithNames" < events.csv
```

### 2.3 TSV / TSVWithNames

```bash
timeplusd client -q "INSERT INTO events FORMAT TabSeparated"       < events.tsv
timeplusd client -q "INSERT INTO events FORMAT TSVWithNames"       < events_h.tsv
```

### 2.4 JSONEachRow (NDJSON, one object per line)

```bash
cat <<EOF | timeplusd client -q "INSERT INTO events FORMAT JSONEachRow"
{"id":10,"name":"carol","ts":"2026-04-20 10:05:00.000"}
{"id":11,"name":"dave", "ts":"2026-04-20 10:05:01.000"}
EOF
```

Bulk-load a large NDJSON file:

```bash
timeplusd client --input_format_allow_errors_num=10 \
  -q "INSERT INTO events FORMAT JSONEachRow" < events.ndjson
```

### 2.5 Parquet / ORC / Arrow

```bash
timeplusd client -q "INSERT INTO events FORMAT Parquet" < events.parquet
timeplusd client -q "INSERT INTO events FORMAT ORC"     < events.orc
timeplusd client -q "INSERT INTO events FORMAT Arrow"   < events.arrow
```

### 2.6 Values (inline literals)

```bash
timeplusd client -q "
  INSERT INTO events (id,name,ts) VALUES
    (100,'eve','2026-04-20 10:10:00.000'),
    (101,'frank','2026-04-20 10:10:01.000')
"
```

### 2.7 Stream a remote file through the client

```bash
curl -s https://example.com/events.csv \
  | timeplusd client -q "INSERT INTO events FORMAT CSVWithNames"
```

### 2.8 Copy between servers

```bash
timeplusd client -h src-host -q "SELECT * FROM events FORMAT Native" \
  | timeplusd client -h dst-host -q "INSERT INTO events FORMAT Native"
```

`Native` is the most efficient format for server-to-server transfers.

---

## 3. Dump data from timeplusd to the local filesystem

Use `--format`/`-f` on the client, or the `FORMAT` clause inside the query.
Redirect `stdout` to a file.

### 3.1 CSV / CSVWithNames

```bash
timeplusd client -q "SELECT * FROM table(events)" --format CSV           > events.csv
timeplusd client -q "SELECT * FROM table(events) FORMAT CSVWithNames"    > events_h.csv
```

> `table(stream_name)` runs a bounded (historical) query against the stream —
> use it whenever you want a finite result you can redirect to a file.

### 3.2 TSV

```bash
timeplusd client -q "SELECT * FROM table(events) FORMAT TSV"             > events.tsv
timeplusd client -q "SELECT * FROM table(events) FORMAT TSVWithNames"    > events_h.tsv
```

### 3.3 JSON / JSONEachRow

```bash
# pretty-ish JSON document with meta + data + statistics
timeplusd client -q "SELECT * FROM table(events) FORMAT JSON"            > events.json

# one JSON object per line (NDJSON)
timeplusd client -q "SELECT * FROM table(events) FORMAT JSONEachRow"     > events.ndjson
```

### 3.4 Parquet / ORC / Arrow

```bash
timeplusd client -q "SELECT * FROM table(events) FORMAT Parquet" > events.parquet
timeplusd client -q "SELECT * FROM table(events) FORMAT ORC"     > events.orc
timeplusd client -q "SELECT * FROM table(events) FORMAT Arrow"   > events.arrow
```

### 3.5 Human-friendly terminal output

```bash
timeplusd client -q "SELECT * FROM table(events) LIMIT 5 FORMAT Pretty"
timeplusd client -q "SELECT * FROM table(events) LIMIT 5 FORMAT PrettyCompact"
timeplusd client -q "SELECT * FROM table(events) LIMIT 1 FORMAT Vertical"
```

Vertical (column per row) is handy for wide rows — equivalent to the `\G`
terminator in MySQL.

### 3.6 SQL `INSERT` statements (for replay)

```bash
timeplusd client -q "SELECT * FROM table(events) FORMAT SQLInsert" > events.sql
```

### 3.7 Compressed dumps

```bash
timeplusd client -q "SELECT * FROM table(events) FORMAT CSVWithNames" \
  | gzip > events.csv.gz

timeplusd client -q "SELECT * FROM table(events) FORMAT JSONEachRow" \
  | zstd > events.ndjson.zst
```

### 3.8 Split large dumps

```bash
timeplusd client -q "SELECT * FROM table(events) FORMAT CSVWithNames" \
  | split -l 1000000 - events_part_
```

---

## 4. Tips

- Default port is `8463` (native TCP). For HTTP, use `8123` with `curl`.
- Streaming queries (`SELECT ... FROM stream_name`) never finish; always wrap
  in `table(...)` or add `WHERE _tp_time < now()` / `LIMIT n` before dumping
  to a file.
- For very large exports, prefer `Native` (binary, columnar) or `Parquet`
  over `CSV`/`JSON` — both are faster and schema-preserving.
- `--input_format_allow_errors_num=N` / `--input_format_allow_errors_ratio=R`
  let you skip malformed rows on import.
- Environment variable `TIMEPLUSD_PASSWORD` (or `CLICKHOUSE_PASSWORD` in
  compatibility mode) avoids putting secrets on the command line.
