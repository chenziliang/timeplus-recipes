-- Leader distributions

WITH leaders AS
  (
    WITH new_leaders AS
      (
        SELECT
          extract(raw, '> (.*.r):') AS stream_shard, to_uint64(extract(raw, 'epoch=(\\d+)')) AS epoch
        FROM
          table(n3_timeplusd_log)
        WHERE
          (position(raw, 'became leader') > 0) AND (_tp_time > '2025-07-30 03:22:00')
        ORDER BY
          _tp_time ASC
      )
    SELECT
      stream_shard, '0x3' AS node, latest(epoch) AS latest_epoch
    FROM
      new_leaders
    GROUP BY
      stream_shard
    UNION ALL
    WITH new_leaders AS
      (
        SELECT
          extract(raw, '> (.*.r):') AS stream_shard, to_uint64(extract(raw, 'epoch=(\\d+)')) AS epoch
        FROM
          table(n2_timeplusd_log)
        WHERE
          (position(raw, 'became leader') > 0) AND (_tp_time > '2025-07-30 03:22:00')
        ORDER BY
          _tp_time ASC
      )
    SELECT
      stream_shard, '0x2' AS node, latest(epoch) AS latest_epoch
    FROM
      new_leaders
    GROUP BY
      stream_shard
    UNION ALL
    WITH new_leaders AS
      (
        SELECT
          extract(raw, '> (.*.r):') AS stream_shard, to_uint64(extract(raw, 'epoch=(\\d+)')) AS epoch
        FROM
          table(n1_timeplusd_log)
        WHERE
          (position(raw, 'became leader') > 0) AND (_tp_time > '2025-07-30 03:22:00')
        ORDER BY
          _tp_time ASC
      )
    SELECT
      stream_shard, '0x1' AS node, latest(epoch) AS latest_epoch
    FROM
      new_leaders
    GROUP BY
      stream_shard
  ), sorted_leaders AS
  (
    SELECT
      *
    FROM
      leaders
    ORDER BY
      stream_shard ASC, latest_epoch ASC
  ), stream_leaders AS
  (
    SELECT
      stream_shard, latest(latest_epoch) AS epoch, latest(node) AS node
    FROM
      sorted_leaders
    GROUP BY
      stream_shard
  )
SELECT
  node, count() AS leader_count
FROM
  stream_leaders
GROUP BY
  node;
