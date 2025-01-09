-- Kafka external stream consume lag in a MV

SELECT node_id, database, stream_name, state_name, state_value 
FROM system.stream_state_log 
WHERE state_name LIKE 'processed_sn_%' OR state_name LIKE 'end_sn_%'   

-- Commit sn and applied sn lag and their storage sizes of streams

SELECT
  node_id, database, name, state_name, latest(state_value) AS state_value, latest(_tp_time) AS ts
FROM
  table(system.stream_state_log)
WHERE
  ((state_name = 'stream_logstore_disk_size') OR (state_name = 'stream_historical_store_disk_size') OR (state_name LIKE 'committed_sn_%') OR (state_name LIKE 'applied_sn_%')) AND (_tp_time > (now() - 5m))
GROUP BY
  node_id, database, name, state_name
SETTINGS
  max_threads = 1, force_backfill_in_order = true


-- Replication status / lagging

SELECT
  node_id, database, name, state_name, state_value, _tp_time
FROM
  system.stream_state_log
WHERE
  state_name = 'quorum_replication_status'