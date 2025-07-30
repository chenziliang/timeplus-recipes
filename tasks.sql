CREATE STREAM node_states (cluster_id string, node_id string, node_state string)

CREATE TASK refresh_node_states
SCHEDULE 5s
TIMEOUT 2s
INTO node_states
AS
  SELECT cluster_id, node_id, node_state FROM system.cluster;
