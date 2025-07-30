-- T+ random stream `r_test` -> Kafka topic `test` -> T+ `test` stream 

-- Create external kafka stream `kafka_test` to point to kafka topic `test` 
-- docker exec 11c6c7813a54 rpk topic create test 
-- rpk topic produce test 

CREATE EXTERNAL STREAM kafka_test(raw string) 
SETTINGS type='kafka', brokers='192.168.1.100:9092', topic='test';

-- Insert to kafka topic test 

CREATE RANDOM STREAM r_test(s string);

INSERT INTO kafka_test SELECT s FROM r_test SETTINGS eps = 100;

-- Ad-hoc streming query external kafka stream

SELECT * FROM kafka_test SETTINGS seek_to='earliest';
SELECT count() FROM kafka_test;

--- Materialized the data to a Timeplus stream

CREATE STREAM test(s string);

CREATE MATERIALIZED VIEW mv_test INTO test AS SELECT raw as s FROM kafka_test;

-- Ad-hoc streaming query Timeplus stream test
SELECT * FROM test;

-- Mapping headers, Kafka record key and record timestamp with customized partitioner for write
CREATE EXTERNAL STREAM ext_k_stream(
    key string,
    value int,
    _tp_message_key string, -- Map to Kafka record key automatically
    _tp_message_headers map(string, string), -- Map to Kafka record headers automatically
    _tp_time datetime64(3), -- Map to Kafka record timestamp automatically
)
SETTINGS type='kafka', brokers='192.168.1.100:9092', topic='test', properties='partitioner=murmur2';

insert into ext_k_stream(key, value, _tp_message_key) values 
('six', 6, 'six'), 
('seven', 7, 'seven'), 
('eight', 8, 'eight'), 
('nine', 9, 'nine'),
('ten', 10, 'ten');

select count() from table(ext_k_stream) group by _tp_shard;

insert into ext_k_stream (key, value, _tp_message_headers) values 
('one', 1, {'test_id': 'smoke_test_32_33', 'idx': '1'}), 
('two', 2, {'test_id': 'smoke_test_32_33', 'idx': '2'}), 
('three', 3, {'test_id': 'smoke_test_32_33', 'idx': '3'}),
('four', 4, {'test_id': 'smoke_test_32_33', 'idx': '4'}),
('five', 5, {'test_id': 'smoke_test_32_33', 'idx': '5'})


select key, value, _tp_message_key, _tp_message_headers from table(ext_k_stream);


-- Avro schema registry

-- 1) Save this file as sensor.avro
```avro
{
  "type": "record",
  "name": "sensor_sample",
  "fields": [
    {
      "name": "timestamp",
      "type": "long",
      "logicalType": "timestamp-millis"
    },
    {
      "name": "identifier",
      "type": "string",
      "logicalType": "uuid"
    },
    {
      "name": "value",
      "type": "long"
    }
  ]
}
```


-- 2) Register this schema against Redpanda schema registry
rpk registry schema create sensor-value --schema sensor.avro 

-- 3) Create `sensors` topic 
rpk topic create sensors

-- 4) Create Kafka external stream with avro schema

CREATE EXTERNAL STREAM ext_sensors
(
  timestamp int64,
  identifier string,
  value int64
)
SETTINGS
  type='kafka', -- required
  brokers='localhost:9092', -- required
  topic='contracts', -- required
  data_format='Avro', -- required
  schema_subject_name='sensor', -- for write avro
  kafka_schema_registry_url='http://localhost:8081'; -- required for Avro

INSERT INTO ext_sensors(timestamp, identifier, value) VALUES (1753853455520, 'dev1', 97);

SELECT * FROM ext_sensors;
