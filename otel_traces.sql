-- Analyze Open Telemetry Trace Outliers

CREATE EXTERNAL STREAM splunk
(
    event string,
    sourcetype string default 'otel_trace'
)
SETTINGS type='http', url='http://127.0.0.1:8088/services/collector', http_header_Authorization='Splunk c9851fde-641d-4a1d-8609-ac808d3a5e5f';


CREATE MATERIALIZED VIEW trace_outliers_mv INTO splunk
AS
WITH outliers AS
(
    SELECT
        trace_id,
        min(start_time) AS start_ts,
        max(end_time) AS end_ts,
        date_diff('ms', start_ts, end_ts) AS span_ms,
        group_array(json_encode(span_id, parent_span_id, name, start_ts, end_ts, attributes)) AS trace_events
    FROM otel_traces
    GROUP BY trace_id
    EMIT AFTER KEY EXPIRE IDENTIFIED BY end_time WITH ONLY MAXSPAN 500ms AND TIMEOUT 2s
)
SELECT json_encode(trace_id, start_ts, end_ts, span_ms, trace_events) AS event
FROM outliers
SETTINGS default_hash_table='hybrid', max_hot_keys=1000000, allow_independent_shard_processing=true

CREATE MATERIALIZED VIEW group_traces_mv INTO splunk
AS
WITH groupped AS
(
    SELECT
        trace_id,
        min(start_time) AS start_ts,
        max(end_time) AS end_ts,
        date_diff('ms', start_ts, end_ts) AS span_ms,
        group_array(json_encode(span_id, parent_span_id, name, start_ts, end_ts, attributes)) AS trace_events
    FROM otel_traces
    GROUP BY trace_id
    EMIT AFTER KEY EXPIRE IDENTIFIED BY end_time WITH MAXSPAN 500ms AND TIMEOUT 2s
)
SELECT json_encode(trace_id, start_ts, end_ts, span_ms, trace_events) AS event
FROM groupped
SETTINGS default_hash_table='hybrid', max_hot_keys=1000000, allow_independent_shard_processing=true
