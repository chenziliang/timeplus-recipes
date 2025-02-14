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

CREATE OR REPLACE VIEW streams_replication_lagging
AS
WITH recent_replication_statuses AS
  (
    SELECT
      node_id AS leader_node, database, name, dimension AS shard, json_extract_array_raw(state_string_value, 'shard_replication_statuses') AS replication_statuses, _tp_time AS ts
    FROM
      system.stream_state_log
    WHERE
      (_tp_time > (now() - 5m)) AND (state_name = 'quorum_replication_status')
    ORDER BY
      _tp_time DESC
    SETTINGS
      query_mode = 'table'
  ), 
latest_replication_statuses AS 
(
  SELECT 
    database, name, to_int(shard) AS shard, earliest(leader_node) AS leader_node, earliest(replication_statuses) AS replication_statuses, earliest(ts) AS ts 
  FROM recent_replication_statuses
  WHERE shard < 1000 
  GROUP BY database, name, shard
), 
flatten AS
  (
    SELECT
      leader_node, database, name, shard, array_join(replication_statuses) AS status, ts
    FROM
      latest_replication_statuses
  )
SELECT
  database, name, shard, leader_node, to_int(status:node) AS peer_node, status:next_sn AS next_sn, status:replicated_sn AS replicated_sn, status:state AS state, status:append_message_flow_paused AS append_paused, status:inflight_messages AS inflight_messages, status:is_learner AS learner, status:recent_active AS recent_active
FROM
  flatten
ORDER BY
  leader, shard ASC;



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


-- Failed materialized view 
-- If a MV which is not running in last 5 minutes, report error
CREATE OR REPLACE  v_failed_mvs 
AS
WITH running_mvs_in_last_5m AS
(
    SELECT
      database, name
    FROM
      system.stream_state_log
    WHERE
      (_tp_time > (now() - 5m)) AND (dimension = 'materialized_view') AND (state_name = 'status') AND (state_string_value = 'ExecutingPipeline')
    ORDER BY _tp_time DESC -- order here to make sure we have the latest state 
    SETTINGS
      query_mode = 'table'
)
SELECT
  database, name, state_string_value, _tp_time
FROM
  system.stream_state_log
WHERE
   (_tp_time > (now() - 5m)) AND (dimension = 'materialized_view') AND (state_name = 'status') AND NOT ((database, name) IN running_mvs_in_last_5m)
SETTINGS
  query_mode = 'table';

-- MVs with lagging >= 1000 for all sources in last 5 minutes
CREATE OR REPLACE v_big_lag_mvs
AS
WITH last_5m_progressing_status AS
(
  SELECT 
    database, name, state_name, dimension, state_value, _tp_time AS ts
  FROM 
    system.stream_state_log
  WHERE 
    (_tp_time > (now() - 5m)) AND (state_name IN ('processed_sn', 'end_sn')) 
  ORDER BY _tp_time DESC -- order here to make sure we have latest state
  SETTINGS
    query_mode = 'table'
),
latest_mv_lagging_per_source AS
(
  SELECT 
    database, name, state_name, latest(state_value) AS state_value, earliest(ts) AS ts
  FROM 
    last_5m_progressing_status
  GROUP BY database, name, state_name, dimension
),
mv_lagging_aggr_per_state AS
( -- Aggregate all sources
  SELECT 
    database, name, state_name, sum(state_value) AS state_value, earliest(ts) AS ts
  FROM 
    last_5m_progressing_status
  GROUP BY database, name, state_name
),
mv_lagging_aggr_per_mv AS
(
  SELECT 
    database, name, group_array(state_name) AS state_names, group_array(state_value) AS state_values, earliest(ts) AS ts
  FROM
    mv_lagging_aggr_per_state 
  GROUP BY database, name
)
SELECT 
  database, name, 
  state_names[1] = 'end_sn' ?  state_values[1] : state_values[2] AS end_sn, 
  state_names[2] = 'processed_sn' ?  state_values[2] : state_values[1] AS processed_sn, 
  end_sn - processed_sn AS lag, 
  ts 
FROM mv_lagging_aggr_per_mv
WHERE lag >= 1000;