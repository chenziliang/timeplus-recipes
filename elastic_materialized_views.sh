#!/bin/bash

# Create MVs
ubuntu@ip-172-31-12-144:~/timeplus$ cat create_mvs.sh

finish()
{
    exit 1
}

trap finish SIGINT


for i in `seq 0 50`
do
    echo "Creating MV mv_$i"
    ./timeplusd client --query "CREATE SCHEDULED MATERIALIZED VIEW IF NOT EXISTS mv_$i INTO sink
    AS
    SELECT
        node_id() as node,
        raw:device AS device,
        raw:region,
        raw:lat::float32 AS lat,
        raw:lon::float32 AS lon,
        raw:temperature::float32,
        raw:_tp_time::datetime64 AS _tp_time
    FROM source
    SETTIGNS checkpoint_settings = 'storage_type=s3;disk_name=ckpt_s3_disk;async=true;interval=5'
done


# Drop MVs

ubuntu@ip-172-31-12-144:~/timeplus$ cat drop_mvs.sh

for i in `seq 1 50`
do
    echo "Dropping MV mv_$i"
    ./timeplusd client --query "DROP STREAM IF EXISTS mv_$i"
    # sleep 5
done


# Fresh cluster

ubuntu@ip-172-31-12-144:~/timeplus$ cat fresh_cluster.sh
#!/bin/bash

finish()
{
    exit 1
}

trap finish SIGINT


while :
do
   ./timeplusd client --query 'INSERT INTO cluster(* except _tp_sn)
    SELECT
    node_id, node_state, node_roles, total_cpus as cpus,
    round(cpu_usage * 100, 1) AS cpu_usage,
    round(os_memory_total_mb / 1024, 0) AS memory_gb,
    round(memory_used_mb / os_memory_total_mb * 100, 1) AS memory_usage,
    timestamp AS _tp_time
FROM system.cluster ORDER BY node_id, node_roles'
   sleep 5
done


# Data gen

ubuntu@ip-172-31-12-144:~/timeplus$ cat json_data_gen.sh
#!/bin/bash

usage()
{
    echo "json_data_gen --eps <eps> --batch-size <batch-size> --total-events <total-events>"
    exit 1
}

total_gen=0

finish()
{
    echo "End of generating total_events=$total_gen" `date`
    exit 1
}

trap finish SIGINT

eps=100
batch_size=100
total_events=1000000000000

while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
        --eps)
            eps="$2"
            shift
            shift
            ;;
        --total-events)
            total_events="$2"
            shift
            shift;;
        --batch-size)
            batch_size="$2"
            shift
            shift;;
        *)
            usage
    esac
done

echo "Generating data at eps=$eps with batch_size=$batch_size total_events=$total_events"

gen_query="SELECT * FROM device_metrics_r LIMIT $batch_size FORMAT JSONEachRow SETTINGS eps=$eps"
insert_query='INSERT INTO source (raw) FORMAT LineAsString'

echo "Data gen query $gen_query"
echo "Data sink query $insert_query"
echo "Start generating" `date` ", ctrl + c to cancel"

while [[ $total_gen -lt $total_events ]]
do
    ./timeplusd client --query "$gen_query" | ./timeplusd client --query "$insert_query"
    total_gen=$((total_gen + batch_size))
    echo "Generated $total_gen events"
done

echo "End of generating" `date`
