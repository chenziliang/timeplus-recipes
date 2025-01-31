-- Separate key / value

CREATE MUTABLE STREAM transactionS
(
  `id` string,
  `from_id` string,
  `to_id` string,
  `value` uint256,
  `meta` fixed_string(256),
  `status` string,
  `block_id` uint64
)
PRIMARY KEY id
SETTINGS shards = 8, log_kvstore=true, logstore_codec='zstd', kvstore_options='max_background_jobs=6;max_write_buffer_number=4;enable_blob_files=true';


-- Create secondary index
ALTER STREAM transactions ADD INDEX sidx (from_id, to_id);

-- Rebuild / refresh secondary index
ALTER STREAM transactions MATERIALIZE INDEX sidx IN SHARD 0;