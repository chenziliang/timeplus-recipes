-- SocketClient metrics
WITH extracted_client_metrics AS
  (
    SELECT
      extract(raw, ' (client.\\w+-\\d+)') AS client, 
      to_uint64(extract(raw, 'connections=(\\d+)')) AS connections, 
      to_uint64(extract(raw, 'failed_connections=(\\d+)')) AS failed_connections, 
      to_uint64(extract(raw, 'total_failed_read=(\\d+)')) AS total_failed_read, 
      to_uint64(extract(raw, 'total_dropped_responses=(\\d+)')) AS total_dropped_responses, 
      to_uint64(extract(raw, 'total_send_requests=(\\d+)')) AS total_send_requests, 
      to_uint64(extract(raw, 'total_failed_send_requests=(\\d+)')) AS total_failed_send_requests, 
      to_uint64(extract(raw, 'total_enqueued_bytes=(\\d+)')) AS total_enqueued_bytes, 
      to_uint64(extract(raw, 'total_send_bytes=(\\d+)')) AS total_send_bytes, 
      to_uint64(extract(raw, 'total_failed_send_bytes=(\\d+)')) AS total_failed_send_bytes, 
      to_uint64(extract(raw, 'total_receive_responses=(\\d+)')) AS total_receive_responses, 
      to_uint64(extract(raw, 'total_receive_bytes=(\\d+)')) AS total_receive_bytes, 
      to_uint64(extract(raw, 'send_requests/s=(\\d+)')) AS send_requests_s, 
      to_uint64(extract(raw, 'send_bytes/s=(\\d+)')) AS send_bytes_s, 
      to_uint64(extract(raw, 'receive_responses/s=(\\d+)')) AS receive_responses_s, 
      to_uint64(extract(raw, 'receive_bytes/s=(\\d+)')) AS receive_bytes_s, 
      _tp_time AS ts
    FROM
      table(n3_timeplusd_log)
    WHERE
      position(raw, 'total_send_requests=') > 0
  )
SELECT
  client, to_uint64(p90(send_bytes_s)) AS send_bytes_s_p90, to_uint64(p90(send_requests_s)) AS send_requests_s_p90
FROM
  extracted_client_metrics
GROUP BY
  client
ORDER BY
  send_bytes_s_p90 ASC, send_requests_s_p90 ASC;

-- Network backpressure 

WITH backpressure_per_stream_node AS
  (
    SELECT
      '0x1' AS node, min(_tp_time) AS min_ts, max(_tp_time) AS max_ts, count() AS count, extract(raw, '> (\\w+\\..*): Backpressure peer node') AS stream, extract(raw, ': Backpressure peer node=(0x\\d+)') AS peer_node
    FROM
      table(n1_timeplusd_log)
    WHERE
      position(raw, 'Backpressure peer node') > 0
    GROUP BY
      peer_node, stream
    UNION ALL
    SELECT
      '0x2' AS node, min(_tp_time) AS min_ts, max(_tp_time) AS max_ts, count() AS count, extract(raw, '> (\\w+\\..*): Backpressure peer node') AS stream, extract(raw, ': Backpressure peer node=(0x\\d+)') AS peer_node
    FROM
      table(n2_timeplusd_log)
    WHERE
      position(raw, 'Backpressure peer node') > 0
    GROUP BY
      peer_node, stream
    UNION ALL
    SELECT
      '0x3' AS node, min(_tp_time) AS min_ts, max(_tp_time) AS max_ts, count() AS count, extract(raw, '> (\\w+\\..*): Backpressure peer node') AS stream, extract(raw, ': Backpressure peer node=(0x\\d+)') AS peer_node
    FROM
      table(n3_timeplusd_log)
    WHERE
      position(raw, 'Backpressure peer node') > 0
    GROUP BY
      peer_node, stream
  )
SELECT
  *
FROM
  backpressure_per_stream_node
ORDER BY
  node ASC, count ASC;


-- Raft Backpressure

WITH backpressure_per_stream_node AS
  (
    SELECT
      '0x1' AS node, min(_tp_time) AS min_ts, max(_tp_time) AS max_ts, count() AS count, extract(raw, '> (\\w+\\..*): Backpressure peer node') AS stream, extract(raw, ': Backpressure peer node=(0x\\d+)') AS peer_node
    FROM
      table(n1_timeplusd_log)
    WHERE
      position(raw, 'Backpressure peer node') > 0
    GROUP BY
      peer_node, stream
    UNION ALL
    SELECT
      '0x2' AS node, min(_tp_time) AS min_ts, max(_tp_time) AS max_ts, count() AS count, extract(raw, '> (\\w+\\..*): Backpressure peer node') AS stream, extract(raw, ': Backpressure peer node=(0x\\d+)') AS peer_node
    FROM
      table(n2_timeplusd_log)
    WHERE
      position(raw, 'Backpressure peer node') > 0
    GROUP BY
      peer_node, stream
    UNION ALL
    SELECT
      '0x3' AS node, min(_tp_time) AS min_ts, max(_tp_time) AS max_ts, count() AS count, extract(raw, '> (\\w+\\..*): Backpressure peer node') AS stream, extract(raw, ': Backpressure peer node=(0x\\d+)') AS peer_node
    FROM
      table(n3_timeplusd_log)
    WHERE
      position(raw, 'Backpressure peer node') > 0
    GROUP BY
      peer_node, stream
  )
SELECT
  node, peer_node, sum(count) AS count
FROM
  backpressure_per_stream_node
GROUP BY
  node, peer_node
ORDER BY
  node ASC, peer_node ASC;

-- Raft recv queue full
SELECT
  extract(raw, 'shard=(\\d+)') AS shard, count()
FROM
  table(timeplusd_errlog0)
WHERE
  position(raw, 'Raft recv queue is full') > 0
GROUP BY
  shard;

-- Socket server
WITH extracted_server_metrics AS
  (
    SELECT
      extract(raw, '(\\w+-server-*\\d*):') AS server, 
      to_uint64(extract(raw, 'current_connections=(\\d+)')) AS current_connections, 
      to_uint64(extract(raw, 'total_connections=(\\d+)')) AS total_connections, 
      to_uint64(extract(raw, 'total_receive_requests=(\\d+)')) AS total_receive_requests, 
      to_uint64(extract(raw, ' total_receive_bytes=(\\d+)')) AS total_receive_bytes, 
      to_uint64(extract(raw, 'total_send_responses=(\\d+)')) AS total_send_responses, 
      to_uint64(extract(raw, 'total_enqueued_bytes=(\\d+)')) AS total_enqueued_bytes, 
      to_uint64(extract(raw, 'total_send_bytes=(\\d+)')) AS total_send_bytes, 
      to_uint64(extract(raw, 'receive_requests/s=(\\d+)')) AS receive_requests_s, 
      to_uint64(extract(raw, 'receive_bytes/s=(\\d+)')) AS receive_bytes_s, 
      to_uint64(extract(raw, 'send_responses/s=(\\d+)')) AS send_responses_s, 
      to_uint64(extract(raw, 'send_bytes/s=(\\d+)')) AS send_bytes_s, 
      _tp_time AS ts
    FROM
      table(n2_timeplusd_log)
    WHERE
      position(raw, 'unauthenticated_connections=') > 0
  )
SELECT
  server, to_uint64(p90(receive_bytes_s)) AS receive_bytes_s_p90, to_uint64(p90(receive_requests_s)) AS receive_requests_s_p90
FROM
  extracted_server_metrics
GROUP BY
  server
ORDER BY
  receive_bytes_s_p90 ASC, receive_requests_s_p90 ASC;
