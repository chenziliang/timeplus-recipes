-- per table compression ratio
SELECT
    table,
    format_readable_size(sum(data_compressed_bytes))   AS compressed,
    format_readable_size(sum(data_uncompressed_bytes)) AS uncompressed,
    round(sum(data_uncompressed_bytes) / sum(data_compressed_bytes), 2) AS ratio
FROM system.parts
WHERE database = 'default' and table = 'rand_target'
GROUP BY table
ORDER BY sum(data_compressed_bytes) DESC;

-- per column compression ratio
SELECT
    table,
    column,
    format_readable_size(sum(column_data_uncompressed_bytes)) AS uncompressed,
    format_readable_size(sum(column_data_compressed_bytes)) AS compressed,
    round(sum(column_data_uncompressed_bytes) / sum(column_data_compressed_bytes), 2) AS ratio
FROM system.parts_columns
WHERE table = 'rand_target'
GROUP BY table, column
ORDER BY table, column;
