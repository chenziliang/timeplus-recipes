#!/usr/bin/env bash
# =============================================================================
# produce.sh — convenience wrapper around produce.py.
#
# Usage:
#   ./produce.sh [count]
#
# Requires (host side):  pip install confluent-kafka protobuf grpcio-tools
# =============================================================================

set -euo pipefail

COUNT="${1:-10}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

if [[ ! -f event_pb2.py ]]; then
  echo "==> Generating producer stub event_pb2.py..."
  uv run python3 -m grpc_tools.protoc -I"$HERE" --python_out="$HERE" "$HERE/event.proto"
fi

echo "==> Producing $COUNT messages per type via produce.py..."
uv run python3 produce.py --count "$COUNT"
