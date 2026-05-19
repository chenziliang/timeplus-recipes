-- ./minio.sh
-- Log on minio http://localhost:9001/ via minioadmin:minioadmin
-- Create `disk` bucket in the minio UI

-- Create S3 disk

CREATE NAMED COLLECTION s3_access AS 
    access_key_id = 'minioadmin',
    secret_access_key = 'minioadmin';


CREATE DISK s3_historical_tier disk(
    named_collection=s3_access, 
    type = 's3',
    endpoint = 'http://localhost:9000/disk/cloudvol/',
);

-- Create storage policy
CREATE STORAGE POLICY s3_tiering AS $$
    volumes:
        hot:
            disk: default
        cold:
            disk: s3_historical_tier
    moving_factor: 0.4 
$$;

-- Use the tier storage
CREATE STREAM hcs_00
(
    i32 int32,
    s string
)
TTL to_datetime(_tp_time) + interval 5 second TO VOLUME 'cold'
SETTINGS storage_policy = 's3_tiering';

-- Insert data
insert into hcs_00 (i32, s) values (1, 'hcs1');

insert into hcs_00 (i32, s) values (2, 'hcs2');

-- Check the tier storage
SELECT partition, name, disk_name FROM system.parts WHERE table = 'hcs_00';
