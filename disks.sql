-- local disk
CREATE DISK local_disk disk(
    type='local', 
    path='/timeplusd-data/tables/'
); 

-- local enrypted disk
CREATE DISK local_encrypted_disk disk(
    type='encrypted', 
    disk='local_disk',
    key_hex='00112233445566778899aabbccddeeff',
    path='tables/',
    algorithm='aes_128_ctr', -- aes_192_ctr, aes_256_ctr
    use_fake_transaction=1
); 

-- shared block storage local file system emulation
CREATE DISK local_shared disk(
    type='local_blob_storage', 
    path='./timeplusd-data/local-shared/'
); 

CREATE DISK local_plain_shared disk(
    type='local_blob_storage', 
    metadata_type='plain',
    path='./timeplusd-data/local-shared/'
); 

-- s3 disk, maintain metadata locally

CREATE DISK s3_disk disk(
    type = 's3',
    endpoint = 'http://localhost:9000/disk/checkpoint/',
    access_key_id = 'minioadmin',
    secret_access_key = 'minioadmin',
    skip_access_check=0
);

-- s3 plain disk, no metadata maintained locally, so doesn't support rename / hardlinks etc

CREATE DISK s3_plain_disk disk(
    type = 's3_plain',
    -- metadata_type='plain',
    endpoint = 'http://localhost:9000/disk/checkpoint/',
    access_key_id = 'minioadmin',
    secret_access_key = 'minioadmin',
    skip_access_check=0
);

-- s3 plain rwritable disk
CREATE DISK s3_plain_rewritable_disk disk(
    type = 's3_plain_rewritable',
    -- metadata_type='plain',
    endpoint = 'http://localhost:9000/disk/checkpoint/',
    access_key_id = 'minioadmin',
    secret_access_key = 'minioadmin',
    skip_access_check=0
);

-- cached
CREATE DISK local_shared_cache disk(
    type='cache', 
    disk='local_shared', 
    path='./timeplusd-data/local-shared/', 
    max_size=100000,
    max_file_segment_size=67108864,
    max_elements=100000,
    cache_on_write_operations=0,
    enable_filesystem_qury_cache_limit=0,
    cache_hits_threshold=0,
    bypass_cache_threashold=268435456,
    boundary_alignment=1048576,
    delayed_cleanup_interval_ms=60000
);
