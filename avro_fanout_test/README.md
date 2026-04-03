# Avro Fan-out Test Environment

Local test setup for [`python_avro_fanout_stream.sql`](../python_avro_fanout_stream.sql).

Demonstrates consuming a single Kafka topic that carries mixed Avro schemas, decoding each message, and routing rows into separate Timeplus streams based on schema type.

## Architecture

```
Redpanda topic: mixed-events
  ├── OrderEvent (schema id=1)  ──┐
  └── UserEvent  (schema id=2)  ──┤
                                  │
              INSERT INTO python_avro_fanout
              SELECT raw FROM kafka_source
                                  │
              Python External Stream
              (deserialize Avro, route by schema)
                                  │
                    ┌─────────────┴─────────────┐
                    ▼                           ▼
            Timeplus stream               Timeplus stream
               `orders`                     `users`
```

## Avro Schemas

**`com.example.OrderEvent`**
| field | type |
|---|---|
| `order_id` | string |
| `amount` | double |
| `customer_id` | string |

**`com.example.UserEvent`**
| field | type |
|---|---|
| `user_id` | string |
| `name` | string |
| `email` | string |

## Files

| File | Purpose |
|---|---|
| `docker-compose.yml` | Redpanda (Kafka + Schema Registry) |
| `setup.sh` | Create topic, register both Avro schemas |
| `produce.sh` | Produce mixed Avro messages via `rpk` |
| `timeplus_streams.sql` | Create target streams + start fan-out |

## Prerequisites

- Docker + Docker Compose
- Timeplus Proton or Timeplus Enterprise running on `localhost:8463`
- Python packages installed in Timeplus:

```sql
SYSTEM INSTALL PYTHON PACKAGE 'fastavro';
SYSTEM INSTALL PYTHON PACKAGE 'proton-driver';
```

## Step-by-Step

### 1. Start Redpanda

```bash
docker compose up -d
```

Ports exposed:
- `9092` — Kafka API
- `8081` — Schema Registry
- `9644` — Admin API

Wait until healthy:

```bash
docker exec redpanda rpk cluster info
```

### 2. Create topic and register schemas

```bash
./setup.sh
```

This will:
- Create topic `mixed-events` (3 partitions)
- Register `com.example.OrderEvent` with the Schema Registry
- Register `com.example.UserEvent` with the Schema Registry

Verify:

```bash
curl -s http://localhost:8081/subjects | python3 -m json.tool
```

### 3. Set up Timeplus streams

Run [`timeplus_streams.sql`](timeplus_streams.sql) in Timeplus (via UI or `timeplusd` CLI):

```sql
-- Creates: orders, users streams + kafka_source external stream
-- Then starts: INSERT INTO python_avro_fanout SELECT raw FROM kafka_source
```

The `python_avro_fanout` external stream is defined in [`../python_avro_fanout_stream.sql`](../python_avro_fanout_stream.sql). Create it first, then run `timeplus_streams.sql`.

Update `init_function_parameters` in `python_avro_fanout_stream.sql` to match your environment:

```json
{
  "host": "127.0.0.1",
  "port": 8463,
  "schema_registry": "http://localhost:8081",
  "log_file": "/var/log/avro_fanout.log",
  "log_level": "INFO",
  "stream_map": {
    "com.example.OrderEvent": "orders",
    "com.example.UserEvent": "users"
  }
}
```

### 4. Produce test messages

```bash
./produce.sh            # 5 messages per schema type (default)
./produce.sh 20         # 20 messages per schema type
```

`produce.sh` fetches schema IDs from the registry at runtime, then uses `rpk topic produce --schema-id` to encode JSON as Avro in Confluent wire format.

### 5. Verify fan-out

Query the target streams in Timeplus:

```sql
-- Streaming (live)
SELECT * FROM orders;
SELECT * FROM users;

-- Snapshot (historical)
SELECT * FROM table(orders);
SELECT * FROM table(users);
```

Check the log file for routing activity:

```bash
tail -f /var/log/avro_fanout.log
```

## Tear Down

```bash
docker compose down
```
