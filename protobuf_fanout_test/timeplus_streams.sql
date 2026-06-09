-- =============================================================================
-- timeplus_streams.sql
-- Create the source + 3 target streams in Timeplus to receive fan-out data from
-- python_protobuf_fanout_stream.sql.
--
-- Target stream columns must match the TRANSFORM output in the recipe
-- (NOT necessarily the raw protobuf fields — e.g. `tier` and `status` are
-- derived columns; the click `user_agent`/`ts_ms` fields are not forwarded).
-- =============================================================================

-- OrderEvent  ->  orders   (tier derived from amount: hot if > 500 else warm)
CREATE STREAM IF NOT EXISTS orders
(
    order_id    string,
    amount      float64,
    customer_id string,
    tier        string
);

-- DeviceEvent ->  devices  (status derived from temperature: alert if > 80 else ok)
CREATE STREAM IF NOT EXISTS devices
(
    device_id   string,
    temperature float64,
    status      string
);

-- ClickEvent  ->  clicks   (bot traffic dropped by the transform)
CREATE STREAM IF NOT EXISTS clicks
(
    session_id string,
    url        string
);


-- =============================================================================
-- Source Kafka external stream (raw binary — Timeplus does NOT decode Protobuf)
-- =============================================================================

CREATE EXTERNAL STREAM IF NOT EXISTS kafka_source(raw string)
SETTINGS
    type    = 'kafka',
    brokers = 'localhost:9092',
    topic   = 'mixed-events';


-- =============================================================================
-- Python external stream — Protobuf fan-out.
-- Create it from ../python_protobuf_fanout_stream.sql FIRST, and update its
-- init_function_parameters "proto_path" to the absolute path of THIS directory
-- (protobuf_fanout_test/, where setup.sh generated *_pb2.py).
-- =============================================================================

-- DROP EXTERNAL STREAM IF EXISTS python_protobuf_fanout;   -- recreate if needed
-- (run the CREATE EXTERNAL STREAM from ../python_protobuf_fanout_stream.sql here)


-- =============================================================================
-- Start the fan-out (runs continuously as a background INSERT)
-- =============================================================================

INSERT INTO python_protobuf_fanout SELECT raw FROM kafka_source;


-- =============================================================================
-- Verify: query the target streams
-- =============================================================================

-- Streaming query (unbounded)
-- SELECT * FROM orders;
-- SELECT * FROM devices;
-- SELECT * FROM clicks;

-- Snapshot query (historical data only)
-- SELECT * FROM table(orders);
-- SELECT * FROM table(devices);
-- SELECT * FROM table(clicks);
