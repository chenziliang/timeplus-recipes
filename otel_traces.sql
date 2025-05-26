-- Analyze Open Telemetry Trace Outliers

CREATE STREAM trace_outliers 
(
    trace_id string,
    span_ms uint32,
    trace_events array(string) 
);

CREATE MATERIALIZED VIEW trace_outliers_mv INTO trace_outliers 
AS
SELECT 
    trace_id, 
    date_diff('ms', min(start_time), max(end_time)) AS span_ms, 
    group_array(json_encode(span_id, parent_span_id, name, attributes)) AS trace_events
FROM otel_traces
GROUP BY trace_id
EMIT AFTER KEY EXPIRE IDENTIFIED BY end_time WITH ONLY MAXSPAN 500ms AND TIMEOUT 2s
SETTINGS default_hash_table='hybrid', max_hot_keys=1000000, allow_independent_shard_processing=true;

CREATE STREAM grouped_traces 
(
    trace_id string,
    span_ms uint32,
    trace_events array(string) 
);

CREATE MATERIALIZED VIEW group_traces_mv INTO grouped_traces 
AS
SELECT 
    trace_id, 
    date_diff('ms', min(start_time), max(end_time)) AS span_ms, 
    group_array(json_encode(span_id, parent_span_id, name, attributes)) AS trace_events
FROM otel_traces
GROUP BY trace_id
EMIT AFTER KEY EXPIRE IDENTIFIED BY end_time WITH MAXSPAN 500ms AND TIMEOUT 2s
SETTINGS default_hash_table='hybrid', max_hot_keys=1000000, allow_independent_shard_processing=true;
