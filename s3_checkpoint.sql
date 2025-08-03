-- ./minio.sh
-- Log on minio http://localhost:9001/ via minioadmin:minioadmin
-- Create `disk` bucket in the minio UI

-- Create S3 disk

CREATE DISK s3_ckpt_disk disk(
    type = 's3',
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
