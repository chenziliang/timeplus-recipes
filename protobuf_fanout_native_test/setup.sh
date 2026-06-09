#!/usr/bin/env bash
# =============================================================================
# setup.sh — create the Kafka topic and generate the producer's protobuf stub.
#
# No Schema Registry, and NOTHING is deployed to Timeplus: the .proto text is
# registered inside Timeplus via CREATE FORMAT SCHEMA (timeplus_streams.sql).
# The generated event_pb2.py is only used by produce.py on the producer side.
#
# Usage:
#   ./setup.sh [broker]
#
# Requires (host side):  pip install grpcio-tools
# =============================================================================

set -euo pipefail

BROKER="${1:-localhost:9092}"
TOPIC="events-envelope"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Broker: $BROKER   Topic: $TOPIC"
echo

echo "==> Waiting for Redpanda..."
until docker exec redpanda rpk cluster info &>/dev/null; do
  sleep 1
done
echo "    Redpanda ready."
echo

echo "==> Creating topic '$TOPIC'..."
docker exec redpanda rpk topic create "$TOPIC" \
  --brokers "$BROKER" --partitions 3 --replicas 1 \
  && echo "    Topic created." \
  || echo "    Topic already exists, skipping."
echo

echo "==> Generating producer protobuf stub (event_pb2.py)..."
python3 -m grpc_tools.protoc -I"$HERE" --python_out="$HERE" "$HERE/event.proto"
echo "    Generated: event_pb2.py"
echo

echo "==> Setup complete."
echo "    Next: register the schema + streams with timeplus_streams.sql, then ./produce.sh"
