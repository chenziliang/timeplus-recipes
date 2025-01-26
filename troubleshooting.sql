-- Kafka external stream consume lag in a MV

SELECT node_id, database, stream_name, state_name, state_value 
FROM system.stream_state_log 
WHERE state_name LIKE 'processed_sn_%' OR state_name LIKE 'end_sn_%'   

-- Commit sn and applied sn lag and their storage sizes of streams

WITH sorted_recent_data_points AS
(
    SELECT
        node_id, database, name, state_name, state_value, _tp_time AS ts
    FROM
        table(system.stream_state_log)
    WHERE
    NOT (starts_with(name, 'mv_k_') OR starts_with(name, '_k_')) AND 
    ((state_name = 'stream_logstore_disk_size') OR (state_name = 'stream_historical_store_disk_size') OR (state_name LIKE 'committed_sn_%') OR (state_name LIKE 'applied_sn_%')) AND (_tp_time > (now() - 15m))
    ORDER BY _tp_time ASC
)
SELECT node_id, database, name, state_name, latest(state_value) AS state_value, latest(ts) AS ts 
FROM sorted_recent_data_points 
GROUP BY
    node_id, database, name, state_name
ORDER BY node_id, database, name, state_name;

SELECT
  node_id, database, name, state_name, latest(state_value) AS state_value, latest(_tp_time) AS ts
FROM
  table(system.stream_state_log)
WHERE
  ((state_name = 'stream_logstore_disk_size') OR (state_name = 'stream_historical_store_disk_size') OR (state_name LIKE 'committed_sn_%') OR (state_name LIKE 'applied_sn_%')) AND (_tp_time > (now() - 30m))
GROUP BY
  node_id, database, name, state_name
SETTINGS
  max_threads = 1, force_backfill_in_order = true


-- Replication status / lagging

WITH sorted_recent_data_points AS
  (
    SELECT
      node_id AS leader_node, name, state_string_value AS replication_statuses, _tp_time AS ts
    FROM
      table(system.stream_state_log)
    WHERE
      (state_name = 'quorum_replication_status') AND (_tp_time > (now() - 1m))
    ORDER BY
      _tp_time DESC
  ), latest_data_point AS
  (
    SELECT
      leader_node, earliest(name) AS name, earliest(replication_statuses) AS replication_statuses, earliest(ts) AS ts
    FROM
      sorted_recent_data_points
    GROUP BY
      leader_node
  ), extracted AS
  (
    SELECT
      leader_node, name, replication_statuses:shard AS shard, json_extract_array_raw(replication_statuses, 'shard_replication_statuses') AS statuses, ts
    FROM
      latest_data_point
  ), flatten AS
  (
    SELECT
      leader_node, name, shard, array_join(statuses) AS status, ts
    FROM
      extracted
  )
SELECT
  name, shard, leader_node, to_int(status:node) AS node, status:next_sn AS next_sn, status:replicated_sn AS replicated_sn, status:state AS state, status:append_message_flow_paused AS append_paused, status:inflight_messages AS inflight_messages, status:is_learner AS learner, status:recent_active AS recent_active
FROM
  flatten
ORDER BY
  node, shard ASC;



./programs/timeplusd client -h 127.0.0.1 --port 8463 --user <username> --password <password> --query "WITH sorted_recent_data_points AS
(
    SELECT
        node_id, database, name, state_name, state_value, _tp_time AS ts
    FROM
        table(system.stream_state_log)
    WHERE
    NOT (starts_with(name, 'mv_k_') OR starts_with(name, '_k_')) AND 
    ((state_name = 'stream_logstore_disk_size') OR (state_name = 'stream_historical_store_disk_size') OR (state_name LIKE 'committed_sn_%') OR (state_name LIKE 'applied_sn_%')) AND (_tp_time > (now() - 15m))
    ORDER BY _tp_time ASC
)
SELECT node_id, database, name, state_name, latest(state_value) AS state_value, latest(ts) AS ts 
FROM sorted_recent_data_points 
GROUP BY
    node_id, database, name, state_name
ORDER BY node_id, database, name, state_name FORMAT CSV" > stream_states.csv


./programs/timeplusd client -h 127.0.0.1 --port 8463 --user <username> --password <password> --query "WITH sorted_recent_data_points AS
  (
    SELECT
      node_id AS leader_node, database, name, state_string_value AS replication_statuses, replication_statuses:shard::uint32 AS shard, _tp_time AS ts
    FROM
      table(system.stream_state_log)
    WHERE
      _tp_time > now() - 15m AND (state_name = 'quorum_replication_status') AND (NOT starts_with(name, 'mv_k_')) AND (NOT starts_with(name, '_k_'))
    ORDER BY
      _tp_time DESC
  ), latest_data_point AS
  (
    SELECT
      leader_node, latest(database) as database, name, shard, latest(replication_statuses) AS replication_statuses, latest(ts) AS ts
    FROM
      sorted_recent_data_points
    GROUP BY
      leader_node, name, shard
  ), extracted AS
  (
    SELECT
      leader_node, database, name, shard, json_extract_array_raw(replication_statuses, 'shard_replication_statuses') AS statuses, ts
    FROM
      latest_data_point
  ), flatten AS
  (
    SELECT
      leader_node, database, name, shard, array_join(statuses) AS status, ts
    FROM
      extracted
  )
SELECT
  database, name, shard, leader_node, to_int(status:node) AS node, status:next_sn::int64 AS next_sn, status:replicated_sn::int64 AS replicated_sn, next_sn - replicated_sn as lag, status:state AS state, status:append_message_flow_paused AS append_paused, status:inflight_messages AS inflight_messages, status:is_learner AS learner, status:recent_active AS recent_active
FROM
  flatten
ORDER BY
  database, name, shard, node FORMAT CSV" > rep_lags.csv
