CREATE EXTERNAL TABLE device_metrics_ch
SETTINGS type='clickhouse',
         address='192.33.21.61:9000',
         user='default',
         database='default',
         table='device_metrics';

CREATE TABLE device_metrics
(
    node UInt32,
    device String,
    region String,
    lat Float32,
    lon Float32,
    temperature Float32,
    _tp_time DateTime64(3)
)
ORDER BY device, region;