-- =============================================================================
-- Python External Stream: Avro Fan-out
-- =============================================================================
-- Consumes raw Avro binary data and routes each record to a target Kafka topic
-- determined by its Avro schema (using the Confluent wire format).
--
-- Wire format expected per message:
--   byte 0    : magic byte 0x00
--   bytes 1-4 : schema ID (big-endian uint32)
--   bytes 5+  : Avro-encoded payload
--
-- Routing:
--   topic_map in init_function_parameters maps schema full name → target topic.
--   Any schema not in the map falls back to using the schema full name as topic.
--
-- Usage:
--   -- Source Kafka external stream (raw binary)
--   CREATE EXTERNAL STREAM kafka_source(raw string)
--   SETTINGS type='kafka', brokers='localhost:9092', topic='mixed-events';
--
--   -- Fan-out: decode Avro, route to per-schema target topics
--   INSERT INTO python_avro_fanout SELECT raw FROM kafka_source;
--
-- Requirements (must be installed in Timeplus Python environment):
--   pip install fastavro confluent-kafka requests
-- =============================================================================

CREATE EXTERNAL STREAM python_avro_fanout
(
    -- raw Avro bytes in Confluent wire format (magic byte + schema_id + payload)
    -- Timeplus passes string columns as Python str via latin-1 encoding,
    -- which preserves all byte values 0x00-0xFF without corruption.
    raw string
)
AS $$

import json
import struct
import sys
from io import BytesIO

import requests
import fastavro
from confluent_kafka import Producer

# ---------------------------------------------------------------------------
# Module-level globals (initialized once per stream lifetime via init())
# ---------------------------------------------------------------------------
_producer = None
_registry_url = None
_topic_map = {}        # schema full name  →  target topic name
_schema_cache = {}     # schema_id (int)   →  parsed schema dict

MAGIC_BYTE = 0x00


# ---------------------------------------------------------------------------
# Schema Registry helpers
# ---------------------------------------------------------------------------

def _fetch_schema(schema_id: int) -> dict:
    """Fetch and cache Avro schema by ID from Schema Registry."""
    if schema_id in _schema_cache:
        return _schema_cache[schema_id]
    url = f"{_registry_url}/schemas/ids/{schema_id}"
    resp = requests.get(url, timeout=10)
    resp.raise_for_status()
    schema = json.loads(resp.json()["schema"])
    _schema_cache[schema_id] = schema
    return schema


def _schema_full_name(schema: dict) -> str:
    name = schema.get("name", "unknown")
    namespace = schema.get("namespace", "")
    return f"{namespace}.{name}" if namespace else name


# ---------------------------------------------------------------------------
# Avro wire format: parse and re-serialize
# ---------------------------------------------------------------------------

def _to_bytes(value) -> bytes:
    """
    Timeplus delivers string columns as Python str encoded with latin-1.
    latin-1 is a 1:1 byte-to-char map (code points 0x00-0xFF), so this
    round-trip is lossless even for raw binary data.
    """
    if isinstance(value, bytes):
        return value
    if isinstance(value, str):
        return value.encode("latin-1")
    raise TypeError(f"Unexpected type for raw column: {type(value)}")


def _parse_avro(raw) -> tuple:
    """
    Parse a Confluent wire-format message.
    Returns (schema_id, schema_dict, decoded_record).
    """
    data = _to_bytes(raw)
    if len(data) < 5:
        raise ValueError(f"Message too short ({len(data)} bytes)")
    if data[0] != MAGIC_BYTE:
        raise ValueError(f"Bad magic byte: 0x{data[0]:02x} (expected 0x00)")
    schema_id = struct.unpack(">I", data[1:5])[0]
    payload   = data[5:]
    schema    = _fetch_schema(schema_id)
    record    = fastavro.schemaless_reader(BytesIO(payload), fastavro.parse_schema(schema))
    return schema_id, schema, record


def _serialize_avro(schema_id: int, schema: dict, record: dict) -> bytes:
    """Re-encode a record back into Confluent wire format with the same schema ID."""
    buf = BytesIO()
    fastavro.schemaless_writer(buf, fastavro.parse_schema(schema), record)
    return struct.pack("B", MAGIC_BYTE) + struct.pack(">I", schema_id) + buf.getvalue()


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

def init(config_: str):
    """
    Called once when the external stream starts.

    config_ is a JSON string with the following fields:
    {
        "broker":          "localhost:9092",
        "schema_registry": "http://localhost:8081",
        "topic_map": {
            "com.example.OrderEvent": "orders",
            "com.example.UserEvent":  "users"
        }
    }

    Any schema full name not listed in topic_map will be routed to a topic
    named after the schema full name itself.
    """
    global _producer, _registry_url, _topic_map

    config        = json.loads(config_)
    _registry_url = config["schema_registry"]
    _topic_map    = config.get("topic_map", {})

    _producer = Producer({
        "bootstrap.servers": config["broker"],
        "linger.ms":         5,
        "compression.type":  "snappy",
    })


def deinit():
    """Called once when the external stream shuts down."""
    global _producer
    if _producer is not None:
        _producer.flush()
        _producer = None


# ---------------------------------------------------------------------------
# Write function — called by Timeplus for each batch of rows
# ---------------------------------------------------------------------------

def process(raw_rows):
    """
    raw_rows : list of raw string values, one per row in the batch.

    For each message:
      1. Parse Confluent Avro wire format → schema_id + record
      2. Look up target topic from topic_map (fallback: schema full name)
      3. Re-serialize and produce to the target topic
    """
    for raw in raw_rows:
        try:
            schema_id, schema, record = _parse_avro(raw)
            full_name    = _schema_full_name(schema)
            target_topic = _topic_map.get(full_name, full_name)
            out_bytes    = _serialize_avro(schema_id, schema, record)
            _producer.produce(topic=target_topic, value=out_bytes)
            _producer.poll(0)   # trigger delivery callbacks without blocking
        except Exception as exc:
            # Log and skip the bad message; never crash the batch
            print(f"[avro_fanout] skipping message: {exc}", file=sys.stderr)

    # Flush at end of each batch to bound latency
    _producer.flush()

$$
SETTINGS
    type                    = 'python',
    write_function_name     = 'process',
    init_function_name      = 'init',
    init_function_parameters = '{"broker":"localhost:9092","schema_registry":"http://localhost:18081","topic_map":{}}',
    deinit_function_name    = 'deinit';


-- =============================================================================
-- Example: wire it up
-- =============================================================================

-- 1. Source topic (raw binary, no schema decoding in Timeplus)
CREATE EXTERNAL STREAM kafka_source(raw string)
SETTINGS
    type    = 'kafka',
    brokers = 'localhost:9092',
    topic   = 'mixed-events';

-- 2. Start the fan-out (runs as a materialized view / background task)
INSERT INTO python_avro_fanout SELECT raw FROM kafka_source;
