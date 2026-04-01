-- ./minio.sh
-- Log on minio http://localhost:9001/ via minioadmin:minioadmin
-- Create `disk` bucket in the minio UI

-- Create S3 disk

CREATE NAMED COLLECTION minio1 AS
    endpoint='http://minio:9000',
    access_key_id='minioroot',
    secret_access_key='minioroot';

CREATE EXTERNAL TABLE minio_ext (key string, value int32)
SETTINGS
    type='s3',
    named_collection='minio1',
    bucket='smoketest-0048-named-collection',
    write_to='00_basic/data.json';

CREATE DISK s3_ckpt_disk disk(
    type = 's3_plain',
    endpoint = 'http://localhost:9000/disk/checkpoint/',
    access_key_id = 'minioadmin',
    secret_access_key = 'minioadmin'
);

CREATE RANDOM STREAM devices_r
(
    name string default 'dev_' || to_string(rand() % 100000),
    cpu_util float,
    mem_util float
);

CREATE STREAM null_devices
(
    node uint32,
    name string,
    max_cpu_util float,
    max_mem_util float
)
ENGINE=Null;

CREATE SCHEDULED MATERIALIZED VIEW smv INTO null_devices
AS
SELECT
    node_id() as node,
    name,
    max(cpu_util) AS max_cpu_util,
    max(mem_util) AS max_mem_util
FROM devices_r
SETTINGS checkpoint_settings = 'storage_type=s3;disk_name=s3_ckpt_disk;async=true'
