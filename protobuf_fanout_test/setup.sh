#!/usr/bin/env bash
# =============================================================================
# setup.sh — create topic, generate protobuf stubs, and register Protobuf
#            schemas in the Redpanda Schema Registry.
#
# Usage:
#   ./setup.sh [broker] [schema_registry]
#
# Defaults:
#   broker          = localhost:9092
#   schema_registry = http://localhost:8081
#
# Requires (host side):
#   pip install grpcio-tools          # provides `python -m grpc_tools.protoc`
# =============================================================================

set -euo pipefail

BROKER="${1:-localhost:9092}"
REGISTRY="${2:-http://localhost:8081}"
TOPIC="mixed-events"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Broker:          $BROKER"
echo "==> Schema Registry: $REGISTRY"
echo "==> Topic:           $TOPIC"
echo "==> Working dir:     $HERE"
echo

# -----------------------------------------------------------------------------
# Wait for Redpanda to be ready
# -----------------------------------------------------------------------------
echo "==> Waiting for Redpanda..."
until docker exec redpanda rpk cluster info &>/dev/null; do
  sleep 1
done
echo "    Redpanda ready."
echo

# -----------------------------------------------------------------------------
# Create topic
# -----------------------------------------------------------------------------
echo "==> Creating topic '$TOPIC'..."
docker exec redpanda rpk topic create "$TOPIC" \
  --brokers "$BROKER" \
  --partitions 3 \
  --replicas 1 \
  && echo "    Topic created." \
  || echo "    Topic already exists, skipping."
echo

# -----------------------------------------------------------------------------
# Generate Python protobuf stubs (*_pb2.py) used by BOTH the producer and the
# Timeplus fan-out recipe. The recipe's init_function_parameters "proto_path"
# must point at this directory ($HERE).
# -----------------------------------------------------------------------------
echo "==> Generating protobuf stubs with grpc_tools.protoc..."
python3 -m grpc_tools.protoc \
  -I"$HERE" \
  --python_out="$HERE" \
  "$HERE/order.proto" "$HERE/device.proto" "$HERE/click.proto"
echo "    Generated: order_pb2.py device_pb2.py click_pb2.py"
echo

# -----------------------------------------------------------------------------
# Register Protobuf schemas (subject = message full name, RecordNameStrategy)
# -----------------------------------------------------------------------------
register_proto() {
  local subject="$1" proto_file="$2"
  echo "==> Registering schema: $subject"
  # Wrap the .proto text as a JSON string and POST it with schemaType=PROTOBUF.
  local payload
  payload=$(python3 - "$proto_file" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    schema = f.read()
print(json.dumps({"schemaType": "PROTOBUF", "schema": schema}))
PY
)
  curl -s -X POST \
    -H "Content-Type: application/vnd.schemaregistry.v1+json" \
    --data "$payload" \
    "$REGISTRY/subjects/$subject/versions" \
    | python3 -m json.tool
  echo
}

register_proto "com.example.OrderEvent"  "$HERE/order.proto"
register_proto "com.example.DeviceEvent" "$HERE/device.proto"
register_proto "com.example.ClickEvent"  "$HERE/click.proto"

# -----------------------------------------------------------------------------
# List registered subjects
# -----------------------------------------------------------------------------
echo "==> Registered subjects:"
curl -s "$REGISTRY/subjects" | python3 -m json.tool
echo
echo "==> Setup complete."
echo "    Set \"proto_path\" in python_protobuf_fanout_stream.sql to: $HERE"
