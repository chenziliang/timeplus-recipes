-- Tier 2 storage
CREATE DISK hdd_disk disk(
    type='local',
    path='/var/lib/timeplusd/disks/extra/'
);

-- Tier 3 storage
CREATE NAMED COLLECTION s3_access AS
access_key_id = 'xxx',
secret_access_key = 'yyy'

CREATE DISK s3_historical_tier disk(
    named_collection=s3_access,
    type='s3',
    endpoint='https://s3.us-west-2.amazonaws.com/timeplusd-shared-disk/timeplus/historical/',
    use_environment_credentials=false -- enable if using env vars or IAM role for auth
);

CREATE DISK s3_checkpoint disk(
    named_collection=s3_access,
    type='s3_plain',
    endpoint='https://s3.us-west-2.amazonaws.com/timeplusd-shared-disk/timeplus/checkpoint/',
    use_environment_credentials=false
);

CREATE DISK s3_nativelog disk(
    named_collection=s3_access,
    type='s3_plain',
    endpoint='https://s3.us-west-2.amazonaws.com/timeplusd-shared-disk/timeplus/nativelog/',
    use_environment_credentials=false
);

CREATE STORAGE POLICY s3_tiering as $$
volumes:
    hot:
        disk: default
        volume_priority: 1
    cold:
        disk: s3_historical_tier
        prefer_not_to_merge: true         -- skip merges on S3
        perform_ttl_move_on_insert: false -- background move only
        volume_priority: 2
move_factor: 0.2
$$;

-- 3-tier storage policy
CREATE STORAGE POLICY ssd_hdd_s3_tiering AS $$
volumes:
  hot:
      disk: default
      volume_priority: 1
      max_data_part_size_bytes: 53687091200   -- 50 GB cap, larger parts spill to warm
  warm:
      disk: hdd_disk
      least_used_ttl_ms: 30000
      perform_ttl_move_on_insert: false       -- background move only
      volume_priority: 2
  cold:
      disk: s3_historical_tier
      prefer_not_to_merge: true               -- skip merges on S3
      perform_ttl_move_on_insert: false       -- background move only
      volume_priority: 3
moving_factor: 0.2
$$;

-- SHOW STORAGE POLICIES [[NOT] [I]LIKE 'str'] [LIMIT expr]
-- SHOW STORAGE POLICIES WHERE <predict>.

-- Source generating stream
CREATE RANDOM STREAM r(i int, s string, id string, a array(int)) settings shards=4;

-- Target materialized stream
CREATE STREAM rand_target(i int, s string, id string, a array(int))
TTL to_start_of_hour(_tp_time) + interval 1 hour to volume 'warm',
    to_start_of_hour(_tp_time) + interval 12 hour to volume 'cold'
settings
    shards=4,
    logstore_codec='zstd',
    shared_disk='s3_nativelog',
    ingest_batch_timeout_ms=2000,
    fetch_threads=4,
    storage_policy='ssd_hdd_s3_tiering';

CREATE MATERIALIZED VIEW r_mv INTO rand_target
AS
SELECT * FROM r
SETTINGS eps=100000;
