#!/bin/bash

docker run --pull=always --name=redpanda --rm \
    -v /Users/k/code/docker-volume/redpanda:/var/lib/redpanda \
    -p 9092:9092 \
    redpandadata/redpanda \
    start \
    --overprovisioned \
    --smp 4  \
    --memory 16G \
    --reserve-memory 0M \
    --node-id 0 \
    --advertise-kafka-addr 192.168.1.115 \
    --set "redpanda.auto_create_topics_enabled=false" \
    --set "redpanda.enable_idempotence=true" \
    --check=false

