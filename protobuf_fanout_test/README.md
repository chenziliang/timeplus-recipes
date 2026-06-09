# Protobuf Fan-out Test Environment

Local test setup for [`python_protobuf_fanout_stream.sql`](../python_protobuf_fanout_stream.sql).

Demonstrates consuming a single Kafka topic that carries **mixed Protobuf
schemas**, decoding each message **once**, applying customized (if/else)
routing + transform logic, and fanning out the rows into **three** separate
Timeplus streams.

This is the Protobuf counterpart of [`avro_fanout_test`](../avro_fanout_test).
The important difference from Avro: Protobuf cannot be decoded from a schema
document at runtime — it needs generated message classes — so `setup.sh` runs
`protoc` to produce `*_pb2.py`, and the recipe maps each Schema-Registry id to a
generated class.

## Architecture

```
Redpanda topic: mixed-events
  ├── OrderEvent  (com.example.OrderEvent)  ──┐
  ├── DeviceEvent (com.example.DeviceEvent) ──┤
  └── ClickEvent  (com.example.ClickEvent)  ──┤
                                              │
              INSERT INTO python_protobuf_fanout
              SELECT raw FROM kafka_source
                                              │
              Python External Stream
              (decode protobuf ONCE, custom transform, route by schema id)
                                              │
            ┌─────────────────┬───────────────┴───────────────┐
            ▼                 ▼                                ▼
      Timeplus stream    Timeplus stream                Timeplus stream
        `orders`           `devices`                      `clicks`
     (+ derived tier)   (+ derived status)            (bot clicks dropped)
```

## Protobuf Schemas & Transforms

| `.proto` message | Subject | Target stream | Custom logic in the recipe |
|---|---|---|---|
| `OrderEvent` (order_id, amount, customer_id) | `com.example.OrderEvent` | `orders` | adds `tier` = `hot` if `amount > 500` else `warm` |
| `DeviceEvent` (device_id, temperature, ts_ms) | `com.example.DeviceEvent` | `devices` | adds `status` = `alert` if `temperature > 80` else `ok` |
| `ClickEvent` (session_id, url, user_agent, ts_ms) | `com.example.ClickEvent` | `clicks` | **drops** rows whose `user_agent` contains `bot`; forwards only `session_id`, `url` |

The transform logic lives in one place — the `TRANSFORMS` table in
[`python_protobuf_fanout_stream.sql`](../python_protobuf_fanout_stream.sql).

## Files

| File | Purpose |
|---|---|
| `docker-compose.yml` | Redpanda (Kafka + Schema Registry) |
| `order.proto` / `device.proto` / `click.proto` | the three message schemas |
| `setup.sh` | create topic, generate `*_pb2.py` stubs, register schemas |
| `produce.py` | produce mixed Protobuf messages (Confluent wire format) |
| `produce.sh` | convenience wrapper around `produce.py` |
| `timeplus_streams.sql` | create source + 3 target streams, start fan-out |

## Prerequisites

- Docker + Docker Compose
- Timeplus Proton or Timeplus Enterprise running on `localhost:8463`
- Host Python packages (for produce/setup):

```bash
pip install confluent-kafka protobuf grpcio-tools requests
```

- Python packages installed **in Timeplus** (for the recipe):

```sql
SYSTEM INSTALL PYTHON PACKAGE 'protobuf';
SYSTEM INSTALL PYTHON PACKAGE 'proton-driver';
-- requests is pre-installed
```

## Step-by-Step

### 1. Start Redpanda

```bash
docker compose up -d
```

Ports exposed: `9092` (Kafka), `8081` (Schema Registry), `8082` (REST Proxy), `9644` (Admin).

Wait until healthy:

```bash
docker exec redpanda rpk cluster info
```

### 2. Create topic, generate stubs, register schemas

```bash
./setup.sh
```

This will:
- Create topic `mixed-events` (3 partitions)
- Generate `order_pb2.py`, `device_pb2.py`, `click_pb2.py` with `protoc`
- Register the 3 Protobuf schemas with the Schema Registry

Verify:

```bash
curl -s http://localhost:8081/subjects | python3 -m json.tool
```

### 3. Set up Timeplus streams + the fan-out recipe

First create the Python external stream from
[`../python_protobuf_fanout_stream.sql`](../python_protobuf_fanout_stream.sql).
**Update its `init_function_parameters`** before running it:

- set `proto_path` to the **absolute path of this directory** (where `setup.sh`
  generated the `*_pb2.py` modules — must be readable by the `timeplusd` process)
- adjust `host`/`port`/`user`/`password` and `log_file` for your environment

```json
{
  "host": "127.0.0.1",
  "port": 8463,
  "user": "default",
  "password": "",
  "schema_registry": "http://localhost:8081",
  "proto_path": "/abs/path/to/timeplus-recipes/protobuf_fanout_test",
  "log_file": "/tmp/protobuf_fanout.log",
  "log_level": "INFO",
  "subjects": {
    "com.example.OrderEvent":  {"module": "order_pb2",  "message": "OrderEvent",  "stream": "orders"},
    "com.example.DeviceEvent": {"module": "device_pb2", "message": "DeviceEvent", "stream": "devices"},
    "com.example.ClickEvent":  {"module": "click_pb2",  "message": "ClickEvent",  "stream": "clicks"}
  }
}
```

Then run [`timeplus_streams.sql`](timeplus_streams.sql) to create the source +
3 target streams and start the fan-out:

```sql
-- Creates: orders, devices, clicks + kafka_source external stream
-- Then starts: INSERT INTO python_protobuf_fanout SELECT raw FROM kafka_source
```

### 4. Produce test messages

```bash
./produce.sh            # 10 messages per type (default)
./produce.sh 50         # 50 messages per type
```

### 5. Verify fan-out

```sql
-- Streaming (live)
SELECT * FROM orders;
SELECT * FROM devices;
SELECT * FROM clicks;

-- Snapshot (historical)
SELECT * FROM table(orders);
SELECT * FROM table(devices);
SELECT * FROM table(clicks);
```

Confirm the custom logic took effect:

```sql
-- tier derived from amount
SELECT tier, count() FROM table(orders) GROUP BY tier;
-- status derived from temperature
SELECT status, count() FROM table(devices) GROUP BY status;
-- bot clicks were dropped: clicks count < ClickEvents produced
SELECT count() FROM table(clicks);
```

Check the log file for routing activity:

```bash
tail -f /tmp/protobuf_fanout.log
```

## How it works (wire format)

Each Kafka message is Confluent Protobuf wire format:

```
byte 0      magic byte 0x00
bytes 1-4   schema id (big-endian uint32)
bytes 5..M  message-index array (varint count + indices; single 0x00 for one message)
bytes M+1.. serialized protobuf payload
```

The recipe reads the schema id from the header, looks up the generated message
class + target stream (resolved from the registry at `init`), decodes the
payload, runs the per-stream transform, and bulk-inserts grouped rows via
`proton_driver`.

## Caveats

- **Delivery is at-least-once**, and the `INSERT`s into the 3 streams are
  *outside* Timeplus's checkpoint. On restart, a partially-written batch can
  produce duplicates — make targets idempotent (`mutable`/`versioned_kv` with a
  primary key) or dedup downstream if exactly-once matters.
- A slow target stream blocks the whole batch (head-of-line coupling).
- For high throughput over many partitions, run several fan-out `INSERT … SELECT`
  tasks, each pinned to a partition subset via `SETTINGS shards='0..63'`, etc.

## Tear Down

```bash
docker compose down
rm -f order_pb2.py device_pb2.py click_pb2.py
```
