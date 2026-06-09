# Protobuf Fan-out Test — Native C++ Decode + Python Routing

Local test setup for [`python_protobuf_fanout_native_decode.sql`](../python_protobuf_fanout_native_decode.sql).

This is the **"decode in C++, route in Python"** variant of
[`protobuf_fanout_test`](../protobuf_fanout_test). The Kafka external stream
decodes protobuf **natively in C++** (via `CREATE FORMAT SCHEMA` + the
`ProtobufSingle` format), so the Python external stream receives already-decoded
**typed columns** and only does the routing. No `protoc` stubs, no `protobuf`
package, and no `.proto` files inside Timeplus.

## Architecture

```
Redpanda topic: events-envelope   (PLAIN protobuf Event messages, no framing)
                              │
              kafka_source  ── C++ decodes via ProtobufSingle + FORMAT SCHEMA ──┐
                              │   (typed columns: event_type, order_id, ...)    │
              INSERT INTO python_protobuf_router                                │
              SELECT event_type, order_id, ... FROM kafka_source  <─────────────┘
                              │
              Python External Stream  (routes DECODED columns by event_type)
                              │
            ┌─────────────────┬───────────────┴───────────────┐
            ▼                 ▼                                ▼
        `orders`          `devices`                        `clicks`
     (+ derived tier)   (+ derived status)              (bot clicks dropped)
```

## How it differs from `protobuf_fanout_test`

| | `protobuf_fanout_test` (stub) | this (native decode) |
|---|---|---|
| Who decodes protobuf | Python, with `protoc` stubs | **C++**, via `FORMAT SCHEMA` |
| Timeplus Python packages | `protobuf` + `proton-driver` | **`proton-driver` only** |
| `.proto` / stubs in Timeplus | `*_pb2.py` deployed on `proto_path` | **none** (schema text lives in the server) |
| Topic wire format | Confluent Schema Registry framing | **plain** `SerializeToString()` |
| Schemas on the topic | 3 distinct message types | **1 envelope** message (`event_type` discriminator) |
| Python's job | decode + transform + route | transform + route only |

Use this variant when the data is **plain protobuf** and fits **one envelope
schema**. Use the stub variant for Confluent-framed topics or genuinely distinct
top-level message types.

## The envelope schema (`event.proto`)

| field | type | used by |
|---|---|---|
| `event_type` | string | discriminator: `order` / `device` / `click` |
| `order_id`, `amount`, `customer_id` | string, double, string | orders |
| `device_id`, `temperature` | string, double | devices |
| `session_id`, `url`, `user_agent` | string, string, string | clicks |

Custom logic in the router (`python_protobuf_fanout_native_decode.sql`): `orders`
gets a derived `tier` (`hot` if `amount > 500`), `devices` a derived `status`
(`alert` if `temperature > 80`), and bot clicks (`user_agent` contains `bot`) are
dropped.

## Files

| File | Purpose |
|---|---|
| `docker-compose.yml` | Redpanda (Kafka only — no Schema Registry needed) |
| `event.proto` | the envelope schema (used by the producer; also registered in Timeplus) |
| `setup.sh` | create topic, generate `event_pb2.py` for the producer |
| `produce.py` / `produce.sh` | produce plain protobuf `Event` messages |
| `timeplus_streams.sql` | `FORMAT SCHEMA` + source + 3 target streams + start fan-out |

## Prerequisites

- Docker + Docker Compose
- Timeplus Proton or Timeplus Enterprise on `localhost:8463`
- Host Python (producer/setup): `pip install confluent-kafka protobuf grpcio-tools`
- In Timeplus (router): `SYSTEM INSTALL PYTHON PACKAGE 'proton-driver';`

## Step-by-Step

### 1. Start Redpanda
```bash
docker compose up -d
docker exec redpanda rpk cluster info     # wait until healthy
```

### 2. Create topic + producer stub
```bash
./setup.sh
```

### 3. Register schema + streams in Timeplus
Run [`timeplus_streams.sql`](timeplus_streams.sql) (creates the `FORMAT SCHEMA`,
`kafka_source`, and the 3 target streams). Then create the router from
[`../python_protobuf_fanout_native_decode.sql`](../python_protobuf_fanout_native_decode.sql)
(adjust its `init_function_parameters` for your host/port/creds), and run the
`INSERT INTO python_protobuf_router SELECT ... FROM kafka_source` to start it.

### 4. Produce test messages
```bash
./produce.sh            # 10 per type
./produce.sh 50
```

### 5. Verify
```sql
SELECT * FROM orders;
SELECT * FROM devices;
SELECT * FROM clicks;

SELECT tier,   count() FROM table(orders)  GROUP BY tier;    -- hot / warm
SELECT status, count() FROM table(devices) GROUP BY status;  -- alert / ok
SELECT count() FROM table(clicks);                           -- < clicks produced (bots dropped)
```
```bash
tail -f /tmp/protobuf_router.log
```

## Caveats

- **Plain protobuf only.** Proton has no Confluent-framed protobuf format; a
  Schema-Registry-framed topic will fail to decode here (use the stub variant).
- **One envelope schema.** Native decode is single-message per stream; distinct
  top-level message types on one topic can't be split natively.
- **At-least-once.** As with the stub variant, the routed `INSERT`s are outside
  Timeplus's checkpoint — make targets idempotent or dedup downstream if needed.
- For high throughput over many partitions, run several fan-out `INSERT … SELECT`
  tasks pinned to partition subsets via `SETTINGS shards='0..63'`, etc.

## Tear Down
```bash
docker compose down
rm -f event_pb2.py
```
