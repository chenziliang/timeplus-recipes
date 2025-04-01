-- bin/
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
SETTINGS type='kafka', brokers='192.33.31.61:9092', topic='source_topic', one_message_per_row=true;

CREATE EXTERNAL STREAM sink(
    node uint32,
    device string,
    region string,
    lat float32,
    lon float32,
    temperature float32,
    _tp_time datetime64(3)
)
SETTINGS type='kafka', brokers='192.33.31.61:9092', topic='sink_topic', data_format='JSONEachRow', one_message_per_row=true;

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

-- CREATE s3 ckpt disk

CREATE DISK IF NOT EXISTS ckpt_s3_disk disk(type = 's3_plain', endpoint = 'https://mat-view-ckpt.s3.us-west-2.amazonaws.com/kchen/', access_key_id = '...', secret_access_key = '...');

