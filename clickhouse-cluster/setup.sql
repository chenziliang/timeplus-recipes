SELECT * FROM system.zookeeper WHERE PATH IN ('/', '/clickhouse');

-- Create database on cluster
CREATE DATABASE test_db ON CLUSTER cluster1

-- Create replicated merge tree on cluster
CREATE TABLE test_db.rmt ON CLUSTER cluster1
(
    `s` String,
    `i` Int
)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/rmt/{shard}', '{replica}')
ORDER BY s;

-- Create a distributed table on top
CREATE TABLE rmt_d 
ENGINE = Distributed(cluster1, test_db, rmt, cityHash64('s'));


SELECT count() FROM rmt_d WHERE i > 2 SETTINGS allow_experimental_analyzer=false;
