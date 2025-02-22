-- bin/kafka-topics.sh --create --topic source_topic --bootstrap-server localhost:9092 --partitions 8 --config compression.type=snappy 
-- bin/kafka-topics.sh --describe --topic source_topic --bootstrap-server localhost:9092
-- bin/kafka-topics.sh --create --topic sink_topic --bootstrap-server localhost:9092 --partitions 8 --config compression.type=snappy 
-- bin/kafka-topics.sh --delete --topic source_topic --bootstrap-server localhost:9092

CREATE RANDOM STREAM device_metrics_r
(
    device string DEFAULT 'dev_' || to_string(rand() % 1000),
    region string DEFAULT 'region_' || to_string(rand() % 100),
    lat float32 DEFAULT  rand()/300,
    lon float32 DEFAULT  rand()/200,
    temperature float32 DEFAULT  rand()/100,
    _tp_time datetime64(3) DEFAULT now64(3, 'UTC')
);


CREATE EXTERNAL STREAM source (raw string) 
SETTINGS type='kafka', brokers='', topic='source_topic', one_message_per_row=true; 

CREATE EXTERNAL STREAM sink(
    node uint32,
    device string,
    region string,
    lat float32,
    lon float32,
    temperature float32, 
    _tp_time datetime64(3)
) 
SETTINGS type='kafka', brokers='', topic='sink_topic', data_format='JSONEachRow', one_message_per_row=true; 


CREATE SCHEDULED MATERIALIZED VIEW mv INTO sink
AS
SELECT 
    node_id() as node, 
    raw:device AS device, 
    raw:region, 
    raw:lat::float32 AS lat, 
    raw:lon::float32 AS lon, 
    raw:temperature::float32, 
    raw:_tp_time::datetime64 AS _tp_time 
FROM source
SETTINGS checkpoint_settings='type=auto;storage_type=local_file_system';

-- Monitoring

CREATE STREAM source_kafka_topic_eps
(
    eps uint32
);

CREATE MATERIALIZED VIEW source_kafka_topic_eps_mv INTO source_kafka_topic_eps 
AS
SELECT
  count() AS total_events, lag(total_events, 1, 0) as prev_total_events, (total_events - prev_total_events) / 2 AS eps
FROM
  source
EMIT PERIODIC 2s;

CREATE STREAM sink_kafka_topic_eps
(
    eps uint32
);


CREATE MATERIALIZED VIEW sink_kafka_topic_eps_mv INTO sink_kafka_topic_eps
AS
SELECT
  count() AS total_events, lag(total_events, 1, 0) as prev_total_events, (total_events - prev_total_events) / 2 AS eps
FROM
  sink 
EMIT PERIODIC 2s;

CREATE MATERIALIZED VIEW current_running_node_eps 
AS
SELECT
  node, count() AS total_events, lag(total_events, 1, 0) AS prev_total_events, (total_events - prev_total_events) / 2 AS eps 
FROM
  sink
GROUP BY
  node
ORDER BY node, eps desc
EMIT PERIODIC 2s;


CREATE STREAM cluster 
(
    node_id uint32,
    node_state string,
    node_roles string,
    cpus uint32,
    cpu_usage float32,
    memory_gb uint32,
    memory_usage float32
);