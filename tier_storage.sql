-- ./minio.sh
-- Log on minio http://localhost:9001/ via minioadmin:minioadmin
-- Create `disk` bucket in the minio UI

-- Create S3 disk

CREATE DISK minio_00 disk(
    type = 's3',
    endpoint = 'http://localhost:9000/disk/cloudvol/',
    access_key_id = 'minioadmin',
    secret_access_key = 'minioadmin'
);

-- Create storage policy
CREATE STORAGE POLICY hcs_minio_00 as $$
    volumes:
        hot:
            disk: default
        cold:
            disk: minio_00
    moving_factor: 0.1
$$;

-- Use the tier storage
CREATE STREAM hcs_00
(
    i32 int32,
    s string
)
TTL to_datetime(_tp_time) + interval 5 second TO VOLUME 'cold'
SETTINGS storage_policy = 'hcs_minio_00';

-- Insert data
insert into hcs_00 (i32, s) values (1, 'hcs1');

insert into hcs_00 (i32, s) values (2, 'hcs2');

-- Check the tier storage
SELECT partition, name, disk_name FROM system.parts WHERE table = 'hcs_00';
