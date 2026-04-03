-- =============================================================================
-- Python External Stream: Avro Fan-out → Timeplus Streams
-- =============================================================================
-- Consumes raw Avro binary data, deserializes each record using its schema
-- from Schema Registry, and inserts rows into per-schema target Timeplus streams
-- via proton_driver.
--
-- Wire format expected per message (Confluent / Redpanda):
--   byte 0    : magic byte 0x00
--   bytes 1-4 : schema ID (big-endian uint32)
--   bytes 5+  : Avro-encoded payload
--
-- Routing:
--   stream_map in init_function_parameters maps schema full name → target stream.
--   Any schema not in the map falls back to using the schema full name as the
--   stream name (with dots replaced by underscores for valid SQL identifiers).
--
-- Usage:
--   -- 1. Source Kafka external stream (raw binary, no decoding)
--   CREATE EXTERNAL STREAM kafka_source(raw string)
--   SETTINGS type='kafka', brokers='localhost:9092', topic='mixed-events';
--
--   -- 2. Fan out: decode Avro, insert into per-schema Timeplus streams
--   INSERT INTO python_avro_fanout SELECT raw FROM kafka_source SETTINGS seek_to='earliest';
--
-- Requirements: install packages via SQL (Proton/Timeplus Enterprise 3.0+):
--   SYSTEM INSTALL PYTHON PACKAGE 'fastavro';
--   SYSTEM INSTALL PYTHON PACKAGE 'proton-driver';
--   (requests is pre-installed)
--
-- Ref avro_fanout_test/README.md for a complete end-to-end test setup with Kafka, Schema Registry, and Timeplus.
--=============================================================================

CREATE EXTERNAL STREAM python_avro_fanout
(
    -- raw Avro bytes in Confluent wire format (magic byte + schema_id + payload)
    raw string
)
AS $$

import json
import logging
import logging.handlers
import struct
import sys
from collections import defaultdict
from io import BytesIO

import requests
import fastavro
from proton_driver import client as proton_client

# ---------------------------------------------------------------------------
# Module-level globals (initialized once per stream lifetime via init())
# ---------------------------------------------------------------------------
_tp_client    = None   # proton_driver Client
_registry_url = None   # Schema Registry base URL
_stream_map   = {}     # schema full name  →  target Timeplus stream name
_schema_cache = {}     # schema_id (int)   →  schema dict
_log          = None   # logger



# ---------------------------------------------------------------------------
# Logging setup
# ---------------------------------------------------------------------------

def _setup_logging(log_file: str, level: str = "INFO") -> logging.Logger:
    """
    Configure a RotatingFileHandler logger.
    Falls back to stderr if the log file path cannot be opened.
    """
    logger = logging.getLogger("avro_fanout")
    logger.setLevel(getattr(logging, level.upper(), logging.INFO))
    logger.handlers.clear()

    fmt = logging.Formatter(
        "%(asctime)s [%(levelname)s] %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S",
    )
    try:
        # Rotate at 50 MB, keep 5 backups
        handler = logging.handlers.RotatingFileHandler(
            log_file, maxBytes=50 * 1024 * 1024, backupCount=5, encoding="utf-8"
        )
    except OSError as exc:
        handler = logging.StreamHandler(sys.stderr)
        logger.warning("Cannot open log file %r (%s), falling back to stderr", log_file, exc)

    handler.setFormatter(fmt)
    logger.addHandler(handler)
    return logger

# ---------------------------------------------------------------------------
# Schema Registry helpers
# ---------------------------------------------------------------------------

def _fetch_schema(schema_id: int) -> dict:
    """Fetch and cache Avro schema by ID from Schema Registry."""
    if schema_id in _schema_cache:
        return _schema_cache[schema_id]
    _log.debug("Fetching schema id=%d from registry", schema_id)
    resp = requests.get(f"{_registry_url}/schemas/ids/{schema_id}", timeout=10)
    resp.raise_for_status()
    schema = json.loads(resp.json()["schema"])
    _schema_cache[schema_id] = schema
    _log.info("Cached schema id=%d  name=%s", schema_id, _schema_full_name(schema))
    return schema


def _schema_full_name(schema: dict) -> str:
    name      = schema.get("name", "unknown")
    namespace = schema.get("namespace", "")
    return f"{namespace}.{name}" if namespace else name


def _default_stream_name(full_name: str) -> str:
    """Convert 'com.example.OrderEvent' to 'com_example_OrderEvent'."""
    return full_name.replace(".", "_")


# ---------------------------------------------------------------------------
# Avro wire format parsing
# ---------------------------------------------------------------------------

def _parse_avro(raw) -> tuple:
    """
    Parse a Confluent wire-format message.
    Returns (schema_id, schema_dict, decoded_record_dict).
    """
    data = raw  # PyBytes_FromStringAndSize delivers a Python bytes object directly
    if len(data) < 5:
        raise ValueError(f"Message too short ({len(data)} bytes)")
    if data[0] != 0x00:
        raise ValueError(f"Bad magic byte: 0x{data[0]:02x}")
    schema_id = struct.unpack(">I", data[1:5])[0]
    schema    = _fetch_schema(schema_id)
    record    = fastavro.schemaless_reader(BytesIO(data[5:]), fastavro.parse_schema(schema))
    return schema_id, schema, record


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

def init(config_: str):
    """
    Called once when the external stream starts.

    config_ JSON fields:
    {
        "host":            "127.0.0.1",   -- Timeplus host
        "port":            8463,          -- Timeplus TCP port
        "database":        "default",     -- optional
        "user":            "default",     -- optional
        "password":        "",            -- optional
        "schema_registry": "http://localhost:8081",
        "log_file":        "/var/log/avro_fanout.log",     -- log file path
        "log_level":       "INFO",                         -- optional: DEBUG / INFO / WARNING / ERROR
        "stream_map": {
            "com.example.OrderEvent": "orders",
            "com.example.UserEvent":  "users"
        }
    }

    Schemas not listed in stream_map are routed to a stream named after the
    schema full name (dots replaced with underscores).
    """
    global _tp_client, _registry_url, _stream_map, _log

    config = json.loads(config_)

    _log = _setup_logging(
        log_file = config["log_file"],
        level    = config.get("log_level", "INFO"),
    )

    _registry_url = config["schema_registry"]
    _stream_map   = config.get("stream_map", {})

    _tp_client = proton_client.Client(
        host     = config.get("host", "127.0.0.1"),
        port     = config.get("port", 8463),
        database = config.get("database", "default"),
        user     = config.get("user", "default"),
        password = config.get("password", ""),
    )

    _log.info(
        "avro_fanout started: registry=%s  stream_map=%s",
        _registry_url, _stream_map,
    )


def deinit():
    """Called once when the external stream shuts down."""
    global _tp_client

    if _log:
        _log.info("avro_fanout shutting down")

    if _tp_client is not None:
        _tp_client.disconnect()
        _tp_client = None


# ---------------------------------------------------------------------------
# Write function — called by Timeplus for each batch of rows
# ---------------------------------------------------------------------------

def process(raw_rows):
    """
    raw_rows : list of raw Avro string values, one per row in the batch.

    For each message:
      1. Parse Confluent wire format → schema + decoded record (dict)
      2. Determine target Timeplus stream from stream_map (or schema full name)
      3. Group records by target stream
      4. Bulk INSERT each group with column names derived from the Avro schema
    """
    # Group decoded records by (target_stream, schema) so we can bulk insert
    # Key: (target_stream_name, schema_id)
    # Value: (schema_dict, [record_dict, ...])
    groups = defaultdict(lambda: (None, []))

    for raw in raw_rows:
        try:
            schema_id, schema, record = _parse_avro(raw)
            full_name     = _schema_full_name(schema)
            target_stream = _stream_map.get(full_name, _default_stream_name(full_name))
            key           = (target_stream, schema_id)
            if groups[key][0] is None:
                groups[key] = (schema, [])
            groups[key][1].append(record)
            _log.info("Decoded schema=%s  target=%s", full_name, target_stream)
        except Exception as exc:
            _log.error("Parse error (skipping message): %s", exc)

    # Bulk insert each group into its target stream
    for (target_stream, schema_id), (schema, records) in groups.items():
        if not records:
            continue
        try:
            fields    = [f["name"] for f in schema.get("fields", [])]
            cols      = ", ".join(fields)
            rows      = [[rec[f] for f in fields] for rec in records]
            _tp_client.execute(
                f"INSERT INTO {target_stream} ({cols}) VALUES",
                rows,
            )
            _log.info("inserted %d rows into %s (schema id=%d)", len(records), target_stream, schema_id)
        except Exception as exc:
            _log.error("Insert error into '%s': %s", target_stream, exc)

$$
SETTINGS
    type                     = 'python',
    write_function_name      = 'process',
    init_function_name       = 'init',
    init_function_parameters = '{"host":"127.0.0.1","port":8463,"user":"default","password":"","schema_registry":"http://localhost:8081","log_file":"/tmp/avro_fanout.log","log_level":"INFO","stream_map":{"com.example.OrderEvent": "orders", "com.example.UserEvent": "users"}}',
    deinit_function_name     = 'deinit';


-- =============================================================================
-- Example: wire it up
-- =============================================================================

-- 1. Source Kafka external stream (raw binary, Timeplus does NOT decode Avro)
-- CREATE EXTERNAL STREAM kafka_source(raw string)
-- SETTINGS
--     type    = 'kafka',
--     brokers = 'localhost:9092',
--     topic   = 'mixed-events';

-- 2. Target Timeplus streams (columns must match the Avro schema fields)
-- CREATE STREAM orders(order_id string, amount float64, customer_id string);
-- CREATE STREAM users(user_id string, name string, email string);

-- 3. Start the fan-out (runs continuously as a background INSERT)
-- INSERT INTO python_avro_fanout SELECT raw FROM kafka_source;
