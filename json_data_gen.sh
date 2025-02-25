#!/bin/bash

usage()
{
    echo "json_data_gen --eps <eps> --total_events <total_events>"
    exit 1
}

eps=100
batch_size=1000
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

echo "Generating data at eps=$eps with total_events=$total_events"

gen_query="SELECT * FROM device_metrics_r LIMIT $batch_size FORMAT JSONEachRow SETTINGS eps=$eps"
insert_query='INSERT INTO source (raw) FORMAT LineAsString;

total_gen=0
while [[ $total_gen -ge $total_events ]]
do
    ./timeplusd client --query $gen_query | ./timeplusd client --query $insert_query
    total_gen=$((total_gen + batch_size))
    echo "Generated $total_gen events"
done


