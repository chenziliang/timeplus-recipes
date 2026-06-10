-- =============================================================================
-- Protobuf Fan-out → 3 Timeplus Streams  (C++ native decode + Python routing)
-- =============================================================================
-- This is the "decode in C++, route in Python" variant of
-- python_protobuf_fanout_stream.sql. Instead of handing raw protobuf bytes to
-- Python (which then needs protoc-generated *_pb2.py stubs), the Kafka external
-- stream decodes protobuf NATIVELY in C++ via a CREATE FORMAT SCHEMA + the
-- ProtobufSingle format. The Python external stream then receives already-decoded
-- TYPED COLUMNS and only does the customized if/else routing.
--
-- Pipeline:
--   CREATE FORMAT SCHEMA       -- store the .proto text server-side (no files, no protoc)
--   kafka_source (typed cols)  -- C++ decodes protobuf -> columns      (decode ONCE)
--   INSERT INTO py_router SELECT col1, col2, ... FROM kafka_source
--   py_router (Python)         -- routes decoded columns to 3 streams  (no protobuf in Python)
--
-- Benefits vs the stub recipe:
--   * No protoc, no *_pb2.py, no protobuf version-matching in the Timeplus env.
--   * Heavy decode runs in fast C++; GIL-bound Python only routes -> higher throughput.
--
-- REQUIREMENTS / CONSTRAINTS (read these — they decide whether this fits):
--   1. ONE format schema must cover the topic. Native decode is single-message
--      per stream, so the topic must carry ONE message type. Here we use a flat
--      "envelope" message with an `event_type` discriminator + the union of all
--      fields; Python routes on `event_type`. (Three genuinely distinct top-level
--      message types on one topic cannot be decoded natively — use the stub recipe.)
--   2. PLAIN protobuf only. Proton has no Confluent-framed protobuf format, so the
--      Kafka messages must be raw SerializeToString() bytes — NOT Schema-Registry
--      wire format (no magic byte / schema id / message-index header).
--
-- Install once (only proton-driver is needed in the Timeplus Python env):
--   SYSTEM INSTALL PYTHON PACKAGE 'proton-driver';
--
-- Ref protobuf_fanout_native_test/README.md for a full end-to-end test setup.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Register the envelope schema server-side (no .proto file on disk needed)
-- -----------------------------------------------------------------------------
CREATE FORMAT SCHEMA IF NOT EXISTS event_schema AS '
syntax = "proto3";

message Event {
  string event_type  = 1;   // "order" | "device" | "click"

  // OrderEvent fields
  string order_id    = 2;
  double amount      = 3;
  string customer_id = 4;

  // DeviceEvent fields
  string device_id   = 5;
  double temperature = 6;

  // ClickEvent fields
  string session_id  = 7;
  string url         = 8;
  string user_agent  = 9;
}
' TYPE Protobuf;


-- -----------------------------------------------------------------------------
-- 2. Kafka source — C++ decodes protobuf into typed columns (one decode, once)
-- -----------------------------------------------------------------------------
-- CREATE EXTERNAL STREAM kafka_source
-- (
--     event_type  string,
--     order_id    string,
--     amount      float64,
--     customer_id string,
--     device_id   string,
--     temperature float64,
--     session_id  string,
--     url         string,
--     user_agent  string
-- )
-- SETTINGS
--     type='kafka', brokers='localhost:9092', topic='events-envelope',
--     data_format='ProtobufSingle', format_schema='event_schema:Event';


-- -----------------------------------------------------------------------------
-- 3. Python router — receives DECODED columns, applies custom if/else, fans out
-- -----------------------------------------------------------------------------
CREATE EXTERNAL STREAM python_protobuf_router
(
    event_type  string,
    order_id    string,
    amount      float64,
    customer_id string,
    device_id   string,
    temperature float64,
    session_id  string,
    url         string,
    user_agent  string
)
AS $$

import json
import logging
import logging.handlers
import sys

from proton_driver import client as proton_client

_tp_client = None   # proton_driver Client
_log       = None   # logger


def _setup_logging(log_file: str, level: str = "INFO") -> logging.Logger:
    logger = logging.getLogger("protobuf_router")
    logger.setLevel(getattr(logging, level.upper(), logging.INFO))
    logger.handlers.clear()
    fmt = logging.Formatter("%(asctime)s [%(levelname)s] %(message)s", datefmt="%Y-%m-%dT%H:%M:%S")
    try:
        handler = logging.handlers.RotatingFileHandler(
            log_file, maxBytes=50 * 1024 * 1024, backupCount=5, encoding="utf-8")
    except OSError as exc:
        handler = logging.StreamHandler(sys.stderr)
        logger.warning("Cannot open log file %r (%s), falling back to stderr", log_file, exc)
    handler.setFormatter(fmt)
    logger.addHandler(handler)
    return logger


def init(config_: str):
    """
    config_ JSON (no credentials — see below):
    {
        "host":"127.0.0.1", "port":8463, "database":"default",
        "log_file":"/tmp/protobuf_router.log", "log_level":"INFO"
    }

    Credentials are NOT hard-coded. timeplusd injects the ephemeral local-API
    credentials __timeplus_local_api_user / __timeplus_local_api_password into
    this module's namespace; we use those to connect back to Timeplus.
    """
    global _tp_client, _log
    config = json.loads(config_)
    _log = _setup_logging(config.get("log_file", "/tmp/protobuf_router.log"),
                          config.get("log_level", "INFO"))
    _tp_client = proton_client.Client(
        host     = config.get("host", "127.0.0.1"),
        port     = config.get("port", 8463),
        database = config.get("database", "default"),
        user     = __timeplus_local_api_user,      # injected ephemeral credentials
        password = __timeplus_local_api_password,
    )
    _log.info("protobuf_router started")


def deinit():
    global _tp_client
    if _log:
        _log.info("protobuf_router shutting down")
    if _tp_client is not None:
        _tp_client.disconnect()
        _tp_client = None


def _text(v):
    """
    Timeplus passes string columns to Python as `bytes`
    (PyBytes_FromStringAndSize); decode to str at the boundary so comparisons
    like et == "order" work. Non-bytes values pass through unchanged.
    """
    return v.decode("utf-8") if isinstance(v, (bytes, bytearray)) else v


# ---------------------------------------------------------------------------
# Write function: args are DECODED columns (one Python list per column), in the
# declared column order. String columns arrive as bytes — see _text().
# This is the single place for customized routing logic.
# ---------------------------------------------------------------------------
def process(event_type, order_id, amount, customer_id,
            device_id, temperature, session_id, url, user_agent):
    orders, devices, clicks = [], [], []

    for i in range(len(event_type)):
        et = _text(event_type[i])
        if et == "order":
            # derive tier from amount
            orders.append([_text(order_id[i]), amount[i], _text(customer_id[i]),
                           "hot" if amount[i] > 500 else "warm"])
        elif et == "device":
            # derive status from temperature
            devices.append([_text(device_id[i]), temperature[i],
                            "alert" if temperature[i] > 80 else "ok"])
        elif et == "click":
            # drop bot traffic
            if "bot" not in _text(user_agent[i]).lower():
                clicks.append([_text(session_id[i]), _text(url[i])])
        else:
            _log.warning("Unknown event_type %r; skipping", et)

    try:
        if orders:
            _tp_client.execute("INSERT INTO orders (order_id, amount, customer_id, tier) VALUES", orders)
        if devices:
            _tp_client.execute("INSERT INTO devices (device_id, temperature, status) VALUES", devices)
        if clicks:
            _tp_client.execute("INSERT INTO clicks (session_id, url) VALUES", clicks)
        _log.info("routed batch: %d orders, %d devices, %d clicks",
                  len(orders), len(devices), len(clicks))
    except Exception as exc:
        _log.error("Insert error: %s", exc)
        raise   # re-raise so the source offset is not advanced past unwritten data

$$
SETTINGS
    type                     = 'python',
    write_function_name      = 'process',
    init_function_name       = 'init',
    init_function_parameters = '{"host":"127.0.0.1","port":8463,"database":"default","log_file":"/tmp/protobuf_router.log","log_level":"INFO"}',
    deinit_function_name     = 'deinit';


-- -----------------------------------------------------------------------------
-- 4. Target streams (columns match the TRANSFORM output)
-- -----------------------------------------------------------------------------
-- CREATE STREAM orders (order_id string, amount float64, customer_id string, tier string);
-- CREATE STREAM devices(device_id string, temperature float64, status string);
-- CREATE STREAM clicks (session_id string, url string);


-- -----------------------------------------------------------------------------
-- 5. Start the fan-out: select decoded columns, route through the Python stream
-- -----------------------------------------------------------------------------
-- INSERT INTO python_protobuf_router
-- SELECT event_type, order_id, amount, customer_id, device_id, temperature,
--        session_id, url, user_agent
-- FROM kafka_source;
