-- Kafka external stream consume lag in a MV

SELECT node_id, database, stream_name, state_name, state_value 
FROM system.stream_state_log 
WHERE state_name LIKE 'processed_sn_%' OR state_name LIKE 'end_sn_%'   

-- Commit sn and applied sn lag and their storage sizes of streams

SELECT * FROM table(system.stream_state_log) 
WHERE name IN ('stream1', 'stream2', 'stream3') 
    AND (state_name = 'stream_logstore_disk_size' OR state_name = 'stream_historical_store_disk_size' OR state_name LIKE 'committed_sn_%' OR state_name LIKE 'applied_sn_%')