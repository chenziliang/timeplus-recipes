-- Tier 2 storage
CREATE DISK hdd_disk disk(
    type='local',
    path='/var/lib/timeplusd/disks/extra/'
);

-- Tier 3 storage
CREATE NAMED COLLECTION s3_access AS 
access_key_id = 'xxx',
secret_access_key = 'yyy'

CREATE DISK s3_historical_tier disk(named_collection=s3_access, type='s3', endpoint='https://s3.us-west-2.amazonaws.com/timeplusd-shared-disk/timeplus/historical/');

CREATE DISK s3_checkpoint disk(named_collection=s3_access, type='s3_plain', endpoint='https://s3.us-west-2.amazonaws.com/timeplusd-shared-disk/timeplus/checkpoint/');

CREATE DISK s3_nativelog disk(named_collection=s3_access, type='s3_plain', endpoint='https://s3.us-west-2.amazonaws.com/timeplusd-shared-disk/timeplus/nativelog/');

CREATE STORAGE POLICY s3_tiering as $$
volumes:
    hot:
        disk: default
    cold:
        disk: s3_historical_tier
move_factor: 0.5
$$;

-- 3-tier storage policy
CREATE STORAGE POLICY ssd_hdd_s3_tiering AS $$
      volumes:
          hot:
              disk: default
          warm:
              disk: hdd_disk
          cold:
              disk: s3_historical_tier
      moving_factor: 0.4
$$;

-- Source generating stream
CREATE RANDOM STREAM r(i int, s string, id string, a array(int)) settings shards=4;

-- Target materialized stream
CREATE STREAM rand_target(i int, s string, id string, a array(int))
TTL to_start_of_hour(_tp_time) + interval 1 hour to volume 'warm',
    to_start_of_hour(_tp_time) + interval 12 hour to volume 'cold'
settings 
    shards=4, 
    shared_disk='s3_nativelog',
    storage_policy='ssd_hdd_s3_tiering';

CREATE MATERIALIZED VIEW r_mv INTO rand_target
AS 
SELECT * FROM r
SETTINGS eps=100000;