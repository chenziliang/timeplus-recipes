#!/bin/bash

# Enable super user but without authentication for admin API, and enable SASL for Kafka API
docker run -d --name redpanda \                                                                                                                                            chore/issue-11688-workload-rebalance ✭ ◼
  -p 9092:9092 \
  -p 8081:8081 \
  -v /Users/k/code/docker-volume/redpanda/data:/var/lib/redpanda/data \
  docker.redpanda.com/redpandadata/redpanda:latest \
  redpanda start \
  --overprovisioned \
  --smp 1 \
  --memory 4G \
  --reserve-memory 0M \
  --node-id 0 \
  --check=false \
  --kafka-addr PLAINTEXT://0.0.0.0:29092,OUTSIDE://0.0.0.0:9092 \
  --advertise-kafka-addr PLAINTEXT://127.0.0.1:29092,OUTSIDE://127.0.0.1:9092 \
  --set redpanda.sasl_enabled=true \
  --set redpanda.admin_api_require_auth=false \
  --set redpanda.superusers="[super]"

# Create a user with the name "admin_user" and password "admin"
docker exec -it redpanda rpk security user create admin_user -p admin

# Enable super user authentication for admin API
docker exec -it redpanda rpk cluster config set admin_api_require_auth true

docker exec -it redpanda rpk cluster config set superusers "[admin_user]" \
  --user admin_user --password admin

# Enble SASL for Kafka API
docker exec -it redpanda rpk cluster config set enable_sasl true \
  --user admin_user --password admin

# Grant permission
docker exec -it redpanda rpk security acl create --allow-principal User:admin_user \
  --operation all \
  --topic any \
  --group any

# docker run --pull=always --name=redpanda --rm \
docker run --name=redpanda --rm \
    -v /Users/k/code/docker-volume/redpanda/data:/var/lib/redpanda/data \
    -p 9092:9092 \
    -p 8082:8081 \
    redpandadata/redpanda \
    start \
    --overprovisioned \
    --smp 2  \
    --memory 4G \
    --reserve-memory 0M \
    --node-id 0 \
    --advertise-kafka-addr 127.0.0.1 \
    --set "redpanda.auto_create_topics_enabled=false" \
    --set "redpanda.enable_idempotence=true" \
    --check=false

