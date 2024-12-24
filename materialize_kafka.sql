-- T+ random stream `r_test` -> Kafka topic `test` -> T+ `test` stream 

-- Create external kafka stream `kafka_test` to point to kafka topic `test` 
-- docker exec 11c6c7813a54 rpk topic create test 

CREATE EXTERNAL STREAM kafka_test(raw string) 
SETTINGS type='kafka', brokers='192.168.1.100:9092', topic='test';

-- Insert to kafka topic test 

CREATE RANDOM STREAM r_test(s string);

INSERT INTO kafka_test SELECT s FROM r_test SETTINGS eps = 100;

-- Ad-hoc streming query external kafka stream

SELECT * FROM kafka_test;
SELECT count() FROM kafka_test;

--- Materialized the data to a Timeplus stream

CREATE STREAM test(s string);

CREATE MATERIALIZED VIEW mv_test INTO test AS SELECT raw FROM kafka_test;

-- Ad-hoc streaming query Timeplus stream test
SELECT * FROM test;
