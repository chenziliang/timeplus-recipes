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

-- Dynamically change log level
SYSTEM SHOW LOGGERS;

-- Set Global Log Level. Valid levels : trace, debug, information, error, fatal 
SYSTEM SET LOG LEVEL <level_name>;
SYSTEM SET LOG LEVEL information;

-- Set Specific Logger Log Level 
SYSTEM SET LOG LEVEL <level_name> FOR '<logger_name>';
SYSTEM SET LOG LEVEL debug FOR 'DiskLocal';

-- Install python packages
SYSTEM INSTALL PYTHON PACKAGE 'requests>2.0'
SYSTEM INSTALL PYTHON PACKAGE 'requests==2.0'
SYSTEM UNINSTALL PYTHON PACKAGE 'requests'
SYSTEM LIST PYTHON PACKAGES