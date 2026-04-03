#!/usr/bin/env bash
# =============================================================================
# setup.sh — create topic and register Avro schemas in Redpanda Schema Registry
#
# Usage:
#   ./setup.sh [broker] [schema_registry]
#
# Defaults:
#   broker          = localhost:9092
#   schema_registry = http://localhost:8081
# =============================================================================

set -euo pipefail

BROKER="${1:-localhost:9092}"
REGISTRY="${2:-http://localhost:8081}"
TOPIC="mixed-events"

echo "==> Broker:          $BROKER"
echo "==> Schema Registry: $REGISTRY"
echo "==> Topic:           $TOPIC"
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
# Register schema: com.example.OrderEvent
# -----------------------------------------------------------------------------
echo "==> Registering schema: com.example.OrderEvent"
ORDER_SCHEMA='{
  "type": "record",
  "namespace": "com.example",
  "name": "OrderEvent",
  "fields": [
    {"name": "order_id",     "type": "string"},
    {"name": "amount",       "type": "double"},
    {"name": "customer_id",  "type": "string"}
  ]
}'

curl -s -X POST \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data "{\"schema\": $(echo "$ORDER_SCHEMA" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')}" \
  "$REGISTRY/subjects/com.example.OrderEvent/versions" \
  | python3 -m json.tool
echo

# -----------------------------------------------------------------------------
# Register schema: com.example.UserEvent
# -----------------------------------------------------------------------------
echo "==> Registering schema: com.example.UserEvent"
USER_SCHEMA='{
  "type": "record",
  "namespace": "com.example",
  "name": "UserEvent",
  "fields": [
    {"name": "user_id",  "type": "string"},
    {"name": "name",     "type": "string"},
    {"name": "email",    "type": "string"}
  ]
}'

curl -s -X POST \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data "{\"schema\": $(echo "$USER_SCHEMA" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')}" \
  "$REGISTRY/subjects/com.example.UserEvent/versions" \
  | python3 -m json.tool
echo

# -----------------------------------------------------------------------------
# List registered subjects
# -----------------------------------------------------------------------------
echo "==> Registered subjects:"
curl -s "$REGISTRY/subjects" | python3 -m json.tool
echo
echo "==> Setup complete."
