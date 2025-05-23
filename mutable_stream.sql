-- Mutable stream

CREATE MUTABLE STREAM transactions
(
  `id` string,
  `from_id` string,
  `to_id` string,
  `value` uint64,
  `status` string,
  `block_id` uint64
)
PRIMARY KEY id
SETTINGS 
  shards = 8, 
  logstore_codec='zstd', -- data compression in logstore 
  log_kvstore=false, 
  kvstore_options='max_background_jobs=6;max_write_buffer_number=4;enable_blob_files=false'; -- Tuning settings for underlying storage engine

-- Data generation
CREATE RANDOM STREAM r_transactions
(
  `id` string default 'id_' || to_string(rand64()), 
  `from_id` string default 'from_id_' || to_string(rand64() % 1000000), 
  `to_id` string default 'to_id_' || to_string(rand64() % 1000000), 
  `value` uint64, 
  `status` string, 
  `block_id` uint64
)
SETTINGS shards = 4;


-- Populate mutable stream with random data with approximate 100 million keys 
INSERT INTO transactions(* except(_tp_sn)) SELECT * FROM r_transactions LIMIT 100000000 SETTINGS eps=20e7;

-- Add secondary indexes for different columns for fast point / range query 
ALTER STREAM transactions ADD INDEX from_idx (from_id); -- secondary index 
ALTER STREAM transactions ADD INDEX to_idx (to_id); -- secondary index 
ALTER STREAM transactions ADD INDEX ts_idx (_tp_time); -- secondary index 

SELECT * FROM table(transactions) LIMIT 10;

-- Approximate count is fast
SELECT count() FROM table(transactions) SETTINGS use_approximate_count=true;

-- Accurate count requires decoding all keys (slower) 
SELECT count() FROM table(transactions);

-- Point query against primary key `id` is fast
SELECT * FROM table(transactions) WHERE id = 'id_10000006';

-- Range query against primary key `id` is fast
SELECT * FROM table(transactions) WHERE id >= 'id_10000006' AND id <= 'id_10000016';

-- Point query against secondary key `from_id` is fast
SELECT * FROM table(transactions) WHERE from_id = 'from_id_18';

-- Range query against secondary key `from_id` is fast
SELECT * FROM table(transactions) WHERE from_id >= 'from_id_18' AND from_id <= 'from_id_19' LIMIT 10 SETTINGS limit_hint=10;

-- Delete by priamry key is fast
DELETE FROM * transactions WHERE id = 'id_10000006';

-- Delete by primary key range is usually fast (depending on how much data will be pruned)
DELETE FROM * transactions WHERE id >= 'id_10000006' and id <= 'id_10000016';

-- Similarly delete by secondary key or key range is usualy fast as long as scondary index can be used.

-- versioned_column

CREATE MUTABLE STREAM v_transactions
(
  `id` string,
  `from_id` string,
  `to_id` string,
  `value` uint64,
  `status` string,
  `block_id` uint64,
  `ts` datetime64
)
PRIMARY KEY id
SETTINGS version_column = 'ts'; 

-- TTL

CREATE MUTABLE STREAM transactions
(
  `id` string,
  `from_id` string,
  `to_id` string,
  `value` uint64,
  `status` string,
  `block_id` uint64
)
PRIMARY KEY id
SETTINGS ttl_seconds = 10; 