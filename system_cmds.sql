-- Format schema cache 
SYSTEM DROP FORMAT SCHEMA CACHE
SYSTEM DROP FORMAT SCHEMA CACHE FOR Protobuf

-- MatView
SYSTEM PAUSE|RESUME|ABORT|RECOVER MATERIALIZED VIEW database.mat_view [LOCAL] [PERMANENT]

-- Stream
SYSTEM PAUSE|RESUME|RECOVER STREAM database.stream shard_id

-- Stream backup
SYSTEM MIGRATE STREAM stream_or_mat_view FROM leader_node TO peer_node

-- Raft
SYSTEM TRANSFER LEADER stream_or_mat_view shard_id FROM leader_node TO peer_node

-- Node
SYSTEM DECOMMISSION NODE victim_node [REPLACED BY target_node]
