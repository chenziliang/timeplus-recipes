-- local disk

CREATE DISK local_shared disk(type='local', path='default'); 

-- s3 disk

CREATE DISK s3_ckpt_disk disk(
    type = 's3',
    endpoint = 'http://localhost:9000/disk/checkpoint/',
    access_key_id = 'minioadmin',
    secret_access_key = 'minioadmin'
);
