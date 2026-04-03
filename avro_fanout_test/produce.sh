#!/usr/bin/env bash
# =============================================================================
# produce.sh — produce mixed Avro messages to Kafka using rpk
#
# rpk encodes JSON stdin as Avro (Confluent wire format) using the schema ID
# fetched from Schema Registry. Each line of JSON becomes one Kafka message.
#
# Usage:
#   ./produce.sh [count] [registry_url]
#
# Defaults:
#   count        = 5   (messages per schema type)
#   registry_url = http://localhost:8081
# =============================================================================

set -euo pipefail

COUNT="${1:-5}"
REGISTRY="${2:-http://localhost:8081}"
TOPIC="mixed-events"

# -----------------------------------------------------------------------------
# Fetch schema IDs from registry
# -----------------------------------------------------------------------------
echo "==> Fetching schema IDs from $REGISTRY..."

ORDER_SCHEMA_ID=$(curl -sf "$REGISTRY/subjects/com.example.OrderEvent/versions/latest" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")

USER_SCHEMA_ID=$(curl -sf "$REGISTRY/subjects/com.example.UserEvent/versions/latest" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")

echo "    com.example.OrderEvent  →  schema id=$ORDER_SCHEMA_ID"
echo "    com.example.UserEvent   →  schema id=$USER_SCHEMA_ID"
echo

# -----------------------------------------------------------------------------
# Helper: generate a pseudo-UUID using date + random
# -----------------------------------------------------------------------------
gen_uuid() {
  printf '%08x-%04x-%04x-%04x-%012x' \
    $RANDOM $RANDOM $RANDOM $RANDOM $((RANDOM * RANDOM))
}

# -----------------------------------------------------------------------------
# Produce OrderEvent messages
# -----------------------------------------------------------------------------
echo "==> Producing $COUNT OrderEvent messages (schema id=$ORDER_SCHEMA_ID)..."

for i in $(seq 1 "$COUNT"); do
  ORDER_ID="order-$(gen_uuid)"
  AMOUNT=$(python3 -c "import random; print(round(random.uniform(1.0, 999.99), 2))")
  CUSTOMER_ID="cust-$((RANDOM % 9000 + 1000))"

  JSON="{\"order_id\":\"$ORDER_ID\",\"amount\":$AMOUNT,\"customer_id\":\"$CUSTOMER_ID\"}"
  echo "    $JSON"

  echo "$JSON" | docker exec -i redpanda \
    rpk topic produce "$TOPIC" \
      --schema-id "$ORDER_SCHEMA_ID" \
      --brokers localhost:9092
done
echo

# -----------------------------------------------------------------------------
# Produce UserEvent messages
# -----------------------------------------------------------------------------
echo "==> Producing $COUNT UserEvent messages (schema id=$USER_SCHEMA_ID)..."

FIRST_NAMES=("Alice" "Bob" "Carol" "Dave" "Eve" "Frank" "Grace" "Heidi")
LAST_NAMES=("Smith" "Jones" "Lee" "Kim" "Patel" "Chen" "Garcia" "Muller")

for i in $(seq 1 "$COUNT"); do
  USER_ID="user-$(gen_uuid)"
  FIRST="${FIRST_NAMES[$((RANDOM % ${#FIRST_NAMES[@]}))]}"
  LAST="${LAST_NAMES[$((RANDOM % ${#LAST_NAMES[@]}))]}"
  NAME="$FIRST $LAST"
  EMAIL="$(echo "$FIRST.$LAST" | tr '[:upper:]' '[:lower:]')@example.com"

  JSON="{\"user_id\":\"$USER_ID\",\"name\":\"$NAME\",\"email\":\"$EMAIL\"}"
  echo "    $JSON"

  echo "$JSON" | docker exec -i redpanda \
    rpk topic produce "$TOPIC" \
      --schema-id "$USER_SCHEMA_ID" \
      --brokers localhost:9092
done
echo

echo "==> Done. Produced $((COUNT * 2)) messages total to '$TOPIC'."
echo
echo "==> Verify with:"
echo "    docker exec redpanda rpk topic consume $TOPIC --brokers localhost:9092 --num 5"
