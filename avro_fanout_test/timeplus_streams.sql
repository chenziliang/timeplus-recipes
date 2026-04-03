-- =============================================================================
-- timeplus_streams.sql
-- Create target streams in Timeplus to receive fan-out data from
-- python_avro_fanout_stream.sql.
--
-- Column names and types must match the Avro schema fields exactly.
-- =============================================================================

-- Stream for com.example.OrderEvent
-- Avro fields: order_id (string), amount (double), customer_id (string)
CREATE STREAM IF NOT EXISTS orders
(
    order_id    string,
    amount      float64,
    customer_id string
);

-- Stream for com.example.UserEvent
-- Avro fields: user_id (string), name (string), email (string)
CREATE STREAM IF NOT EXISTS users
(
    user_id string,
    name    string,
    email   string
);


-- =============================================================================
-- Source Kafka external stream (raw binary — Timeplus does NOT decode Avro)
-- =============================================================================

CREATE EXTERNAL STREAM IF NOT EXISTS kafka_source(raw string)
SETTINGS
    type    = 'kafka',
    brokers = 'localhost:9092',
    topic   = 'mixed-events';


-- =============================================================================
-- Python external stream — Avro fan-out (see python_avro_fanout_stream.sql)
-- Update init_function_parameters with your actual paths/credentials.
-- =============================================================================

-- DROP EXTERNAL STREAM IF EXISTS python_avro_fanout;   -- recreate if needed

-- (run the CREATE EXTERNAL STREAM from python_avro_fanout_stream.sql here,
--  or source it separately)


-- =============================================================================
-- Start the fan-out
-- =============================================================================

INSERT INTO python_avro_fanout SELECT raw FROM kafka_source;


-- =============================================================================
-- Verify: query the target streams
-- =============================================================================

-- Streaming query (unbounded)
-- SELECT * FROM orders;
-- SELECT * FROM users;

-- Snapshot query (historical data only)
-- SELECT * FROM table(orders);
-- SELECT * FROM table(users);
