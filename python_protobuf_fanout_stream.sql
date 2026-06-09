-- =============================================================================
-- Python External Stream: Protobuf Fan-out → 3 Timeplus Streams
-- =============================================================================
-- Consumes raw Protobuf binary data from ONE Kafka topic, decodes each message
-- ONCE, applies customized (if/else) routing + transform logic, and inserts the
-- resulting rows into separate per-type target Timeplus streams via proton_driver.
--
-- This is the Protobuf counterpart of python_avro_fanout_stream.sql. The key
-- difference: unlike Avro, Protobuf cannot be decoded from a schema document at
-- runtime — it needs generated message classes (*_pb2.py from `protoc`). So the
-- recipe maps each Confluent schema id to a generated message class.
--
-- Wire format expected per message (Confluent / Redpanda Protobuf):
--   byte 0      : magic byte 0x00
--   bytes 1-4   : schema id (big-endian uint32)
--   bytes 5..M  : message-index array (varint count, then `count` varints;
--                 the common single-message case is one 0x00 byte)
--   bytes M+1.. : serialized protobuf payload
--
-- Routing & transform (the "customized if/else logic"):
--   schema id  →  (generated message class, target stream)   [resolved at init]
--   For each decoded message, a per-stream TRANSFORM builds the output row and
--   may DROP the record (return None). See the TRANSFORMS table below — this is
--   the single place to edit business logic.
--
-- Requirements (Proton / Timeplus Enterprise — install once):
--   SYSTEM INSTALL PYTHON PACKAGE 'protobuf';
--   SYSTEM INSTALL PYTHON PACKAGE 'proton-driver';
--   (requests is pre-installed)
--   The generated *_pb2.py modules must be readable by the timeplusd process and
--   live under the directory given by "proto_path" in init_function_parameters.
--
-- Ref protobuf_fanout_test/README.md for a complete end-to-end test setup with
-- Kafka, Schema Registry, protoc codegen, and Timeplus.
-- =============================================================================

CREATE EXTERNAL STREAM python_protobuf_fanout
(
    -- raw Protobuf bytes in Confluent wire format (magic + schema_id + msg index + payload)
    raw string
)
AS $$

import importlib
import json
import logging
import logging.handlers
import struct
import sys
from collections import defaultdict

import requests
from proton_driver import client as proton_client

# ---------------------------------------------------------------------------
# Module-level globals (initialized once per stream lifetime via init())
# ---------------------------------------------------------------------------
_tp_client    = None   # proton_driver Client
_registry_url = None   # Schema Registry base URL
_by_id        = {}     # schema_id (int) -> (message_class, target_stream, subject)
_log          = None   # logger


# ===========================================================================
# CUSTOMIZED ROUTING / TRANSFORM LOGIC  (edit here)
# ---------------------------------------------------------------------------
# One handler per target stream. Each receives the decoded protobuf message and
# returns a dict {column: value} to insert, or None to DROP the record.
# The dict keys must match the target stream's column names.
# ===========================================================================

def _xform_orders(msg) -> dict:
    # Derive a "tier" column from the order amount (if/else business logic).
    return {
        "order_id":    msg.order_id,
        "amount":      msg.amount,
        "customer_id": msg.customer_id,
        "tier":        "hot" if msg.amount > 500 else "warm",
    }


def _xform_devices(msg) -> dict:
    # Derive a "status" column from the temperature reading.
    return {
        "device_id":   msg.device_id,
        "temperature": msg.temperature,
        "status":      "alert" if msg.temperature > 80 else "ok",
    }


def _xform_clicks(msg):
    # Drop bot traffic entirely (return None => record is skipped).
    if "bot" in msg.user_agent.lower():
        return None
    return {
        "session_id": msg.session_id,
        "url":        msg.url,
    }


TRANSFORMS = {
    "orders":  _xform_orders,
    "devices": _xform_devices,
    "clicks":  _xform_clicks,
}


# ---------------------------------------------------------------------------
# Logging setup
# ---------------------------------------------------------------------------

def _setup_logging(log_file: str, level: str = "INFO") -> logging.Logger:
    """Configure a RotatingFileHandler logger; fall back to stderr on failure."""
    logger = logging.getLogger("protobuf_fanout")
    logger.setLevel(getattr(logging, level.upper(), logging.INFO))
    logger.handlers.clear()

    fmt = logging.Formatter(
        "%(asctime)s [%(levelname)s] %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S",
    )
    try:
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

def _fetch_schema_id(subject: str) -> int:
    """Return the latest registered schema id for a subject."""
    resp = requests.get(f"{_registry_url}/subjects/{subject}/versions/latest", timeout=10)
    resp.raise_for_status()
    return resp.json()["id"]


# ---------------------------------------------------------------------------
# Confluent Protobuf wire-format parsing
# ---------------------------------------------------------------------------

def _read_varint(buf, pos: int):
    """Read a base-128 varint from buf at pos. Returns (value, new_pos)."""
    result = 0
    shift = 0
    while True:
        b = buf[pos]
        pos += 1
        result |= (b & 0x7F) << shift
        if not (b & 0x80):
            return result, pos
        shift += 7


def _parse_protobuf(raw):
    """
    Parse a Confluent Protobuf wire-format message.
    Returns (schema_id, payload_bytes). The message-index array is consumed and
    discarded (we route by schema id; each schema here has a single message type).
    """
    data = raw if isinstance(raw, (bytes, bytearray)) else raw.encode("latin-1")
    if len(data) < 5:
        raise ValueError(f"Message too short ({len(data)} bytes)")
    if data[0] != 0x00:
        raise ValueError(f"Bad magic byte: 0x{data[0]:02x}")

    schema_id = struct.unpack(">I", data[1:5])[0]

    # Message-index array: a varint count, then `count` varints. The common
    # single-message optimization encodes the array [0] as a single 0 byte.
    pos = 5
    count, pos = _read_varint(data, pos)
    for _ in range(count):
        _, pos = _read_varint(data, pos)

    return schema_id, data[pos:]


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
        "proto_path":      "/abs/path/to/protobuf_fanout_test",  -- dir with *_pb2.py
        "log_file":        "/tmp/protobuf_fanout.log",
        "log_level":       "INFO",        -- optional: DEBUG / INFO / WARNING / ERROR
        "subjects": {
            "com.example.OrderEvent":  {"module": "order_pb2",  "message": "OrderEvent",  "stream": "orders"},
            "com.example.DeviceEvent": {"module": "device_pb2", "message": "DeviceEvent", "stream": "devices"},
            "com.example.ClickEvent":  {"module": "click_pb2",  "message": "ClickEvent",  "stream": "clicks"}
        }
    }

    For each subject we import the generated message class and resolve its
    Schema-Registry id, building a schema_id -> (class, stream) map. The schemas
    must already be registered (run protobuf_fanout_test/setup.sh first).
    """
    global _tp_client, _registry_url, _by_id, _log

    config = json.loads(config_)

    _log = _setup_logging(
        log_file = config["log_file"],
        level    = config.get("log_level", "INFO"),
    )

    _registry_url = config["schema_registry"]

    # Make the generated *_pb2.py modules importable.
    proto_path = config["proto_path"]
    if proto_path not in sys.path:
        sys.path.insert(0, proto_path)

    _by_id = {}
    for subject, spec in config.get("subjects", {}).items():
        module      = importlib.import_module(spec["module"])
        msg_class   = getattr(module, spec["message"])
        target      = spec["stream"]
        if target not in TRANSFORMS:
            raise ValueError(f"No TRANSFORM defined for target stream '{target}'")
        schema_id   = _fetch_schema_id(subject)
        _by_id[schema_id] = (msg_class, target, subject)
        _log.info("Mapped schema id=%d  subject=%s  ->  %s.%s  ->  stream '%s'",
                  schema_id, subject, spec["module"], spec["message"], target)

    _tp_client = proton_client.Client(
        host     = config.get("host", "127.0.0.1"),
        port     = config.get("port", 8463),
        database = config.get("database", "default"),
        user     = config.get("user", "default"),
        password = config.get("password", ""),
    )

    _log.info("protobuf_fanout started: registry=%s  schema_ids=%s",
              _registry_url, sorted(_by_id.keys()))


def deinit():
    """Called once when the external stream shuts down."""
    global _tp_client
    if _log:
        _log.info("protobuf_fanout shutting down")
    if _tp_client is not None:
        _tp_client.disconnect()
        _tp_client = None


# ---------------------------------------------------------------------------
# Write function — called by Timeplus for each batch of rows
# ---------------------------------------------------------------------------

def process(raw_rows):
    """
    raw_rows : list of raw Protobuf string/bytes values, one per row in the batch.

    For each message:
      1. Parse Confluent wire format  -> schema id + payload bytes
      2. Look up message class + target stream by schema id
      3. Decode payload, run the per-stream TRANSFORM (may drop the record)
      4. Group resulting rows by target stream and bulk INSERT each group
    """
    # target_stream -> (ordered column list, [row_values, ...])
    groups = defaultdict(lambda: (None, []))

    for raw in raw_rows:
        try:
            schema_id, payload = _parse_protobuf(raw)
            mapping = _by_id.get(schema_id)
            if mapping is None:
                _log.warning("Unknown schema id=%d (not in subjects map); skipping", schema_id)
                continue

            msg_class, target, _subject = mapping
            msg = msg_class()
            msg.ParseFromString(payload)        # <-- single protobuf decode

            row_dict = TRANSFORMS[target](msg)  # <-- customized if/else logic
            if row_dict is None:
                _log.debug("Record dropped by transform for stream '%s'", target)
                continue

            cols, rows = groups[target]
            if cols is None:
                cols = list(row_dict.keys())
                groups[target] = (cols, rows)
            rows.append([row_dict[c] for c in cols])
        except Exception as exc:
            _log.error("Parse/transform error (skipping message): %s", exc)

    # Bulk insert each group into its target stream
    for target, (cols, rows) in groups.items():
        if not rows:
            continue
        try:
            col_list = ", ".join(cols)
            _tp_client.execute(f"INSERT INTO {target} ({col_list}) VALUES", rows)
            _log.info("inserted %d rows into %s", len(rows), target)
        except Exception as exc:
            _log.error("Insert error into '%s': %s", target, exc)

$$
SETTINGS
    type                     = 'python',
    write_function_name      = 'process',
    init_function_name       = 'init',
    init_function_parameters = '{"host":"127.0.0.1","port":8463,"user":"default","password":"","schema_registry":"http://localhost:8081","proto_path":"/CHANGE/ME/protobuf_fanout_test","log_file":"/tmp/protobuf_fanout.log","log_level":"INFO","subjects":{"com.example.OrderEvent":{"module":"order_pb2","message":"OrderEvent","stream":"orders"},"com.example.DeviceEvent":{"module":"device_pb2","message":"DeviceEvent","stream":"devices"},"com.example.ClickEvent":{"module":"click_pb2","message":"ClickEvent","stream":"clicks"}}}',
    deinit_function_name     = 'deinit';


-- =============================================================================
-- Example: wire it up   (see protobuf_fanout_test/ for the full harness)
-- =============================================================================

-- 1. Source Kafka external stream (raw binary, Timeplus does NOT decode Protobuf)
-- CREATE EXTERNAL STREAM kafka_source(raw string)
-- SETTINGS type='kafka', brokers='localhost:9092', topic='mixed-events';

-- 2. Target Timeplus streams (columns must match the TRANSFORM output)
-- CREATE STREAM orders(order_id string, amount float64, customer_id string, tier string);
-- CREATE STREAM devices(device_id string, temperature float64, status string);
-- CREATE STREAM clicks(session_id string, url string);

-- 3. Start the fan-out (runs continuously as a background INSERT)
-- INSERT INTO python_protobuf_fanout SELECT raw FROM kafka_source;
