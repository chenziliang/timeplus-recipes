#!/usr/bin/env bash
# =============================================================================
# produce.sh — convenience wrapper around produce.py.
#
# Ensures the generated *_pb2.py stubs exist (creates them if missing), then
# produces mixed Protobuf messages to the topic.
#
# Usage:
#   ./produce.sh [count] [registry_url]
#
# Defaults:
#   count        = 10
#   registry_url = http://localhost:8081
#
# Requires (host side):
#   pip install confluent-kafka protobuf grpcio-tools
# =============================================================================

set -euo pipefail

COUNT="${1:-10}"
REGISTRY="${2:-http://localhost:8081}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$HERE"

# Generate stubs if they are missing (setup.sh normally does this).
if [[ ! -f order_pb2.py || ! -f device_pb2.py || ! -f click_pb2.py ]]; then
  echo "==> Generating protobuf stubs..."
  python3 -m grpc_tools.protoc -I"$HERE" --python_out="$HERE" \
    "$HERE/order.proto" "$HERE/device.proto" "$HERE/click.proto"
fi

echo "==> Producing $COUNT messages per type via produce.py..."
python3 produce.py --registry "$REGISTRY" --count "$COUNT"
