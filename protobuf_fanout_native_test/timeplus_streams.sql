-- =============================================================================
-- timeplus_streams.sql  (native-decode variant)
--
-- C++ decodes protobuf via CREATE FORMAT SCHEMA + ProtobufSingle; the Python
-- external stream (python_protobuf_router) only routes the decoded columns.
--
-- Order of operations:
--   1. Run this file's FORMAT SCHEMA + kafka_source + target streams.
--   2. Create python_protobuf_router from ../python_protobuf_fanout_native_decode.sql
--      (adjust its init_function_parameters for host/port/creds).
--   3. Run the INSERT below to start the fan-out.
-- =============================================================================

-- 1. Envelope schema, stored server-side (no .proto file, no protoc)
CREATE FORMAT SCHEMA IF NOT EXISTS event_schema AS '
syntax = "proto3";

message Event {
  string event_type  = 1;
  string order_id    = 2;
  double amount      = 3;
  string customer_id = 4;
  string device_id   = 5;
  double temperature = 6;
  string session_id  = 7;
  string url         = 8;
  string user_agent  = 9;
}
' TYPE Protobuf;


-- 2. Kafka source — C++ decodes PLAIN protobuf into typed columns (decode once)
CREATE EXTERNAL STREAM IF NOT EXISTS kafka_source
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
SETTINGS
    type        = 'kafka',
    brokers     = 'localhost:9092',
    topic       = 'events-envelope',
    data_format = 'ProtobufSingle',
    format_schema = 'event_schema:Event';


-- 3. Target streams (columns match the router's TRANSFORM output)
CREATE STREAM IF NOT EXISTS orders
(
    order_id    string,
    amount      float64,
    customer_id string,
    tier        string
);

CREATE STREAM IF NOT EXISTS devices
(
    device_id   string,
    temperature float64,
    status      string
);

CREATE STREAM IF NOT EXISTS clicks
(
    session_id string,
    url        string
);


-- 4. Create python_protobuf_router from ../python_protobuf_fanout_native_decode.sql
--    (run that CREATE EXTERNAL STREAM here, or source it separately)


-- 5. Start the fan-out: decoded columns -> Python router -> 3 streams
INSERT INTO python_protobuf_router
SELECT event_type, order_id, amount, customer_id, device_id, temperature,
       session_id, url, user_agent
FROM kafka_source;


-- =============================================================================
-- Verify
-- =============================================================================
-- SELECT * FROM orders;   SELECT * FROM devices;   SELECT * FROM clicks;
-- SELECT tier,   count() FROM table(orders)  GROUP BY tier;
-- SELECT status, count() FROM table(devices) GROUP BY status;
-- SELECT count() FROM table(clicks);   -- < clicks produced (bots dropped)
