#!/usr/bin/env python3
"""
produce.py — produce mixed Avro messages to a Kafka topic.

Fetches schema IDs from Schema Registry, serializes records in Confluent
wire format (0x00 + 4-byte schema_id + avro payload), and publishes them
to the configured topic.

Usage:
  pip install confluent-kafka fastavro requests
  python produce.py [--broker localhost:9092] [--registry http://localhost:8081]
                    [--topic mixed-events] [--count 10]
"""

import argparse
import json
import random
import struct
import time
import uuid
from io import BytesIO

import fastavro
import requests
from confluent_kafka import Producer

# ---------------------------------------------------------------------------
# Schema definitions (must match what was registered in setup.sh)
# ---------------------------------------------------------------------------

SCHEMAS = {
    "com.example.OrderEvent": {
        "type": "record",
        "namespace": "com.example",
        "name": "OrderEvent",
        "fields": [
            {"name": "order_id",    "type": "string"},
            {"name": "amount",      "type": "double"},
            {"name": "customer_id", "type": "string"},
        ],
    },
    "com.example.UserEvent": {
        "type": "record",
        "namespace": "com.example",
        "name": "UserEvent",
        "fields": [
            {"name": "user_id", "type": "string"},
            {"name": "name",    "type": "string"},
            {"name": "email",   "type": "string"},
        ],
    },
}


# ---------------------------------------------------------------------------
# Sample record generators
# ---------------------------------------------------------------------------

def _random_order() -> dict:
    return {
        "order_id":    str(uuid.uuid4()),
        "amount":      round(random.uniform(1.0, 999.99), 2),
        "customer_id": f"cust-{random.randint(1000, 9999)}",
    }


def _random_user() -> dict:
    first = random.choice(["Alice", "Bob", "Carol", "Dave", "Eve"])
    last  = random.choice(["Smith", "Jones", "Lee", "Kim", "Patel"])
    return {
        "user_id": str(uuid.uuid4()),
        "name":    f"{first} {last}",
        "email":   f"{first.lower()}.{last.lower()}@example.com",
    }


GENERATORS = {
    "com.example.OrderEvent": _random_order,
    "com.example.UserEvent":  _random_user,
}


# ---------------------------------------------------------------------------
# Schema Registry helpers
# ---------------------------------------------------------------------------

def get_schema_id(registry_url: str, subject: str) -> int:
    """Return the latest schema ID for a subject."""
    url  = f"{registry_url}/subjects/{subject}/versions/latest"
    resp = requests.get(url, timeout=10)
    resp.raise_for_status()
    return resp.json()["id"]


# ---------------------------------------------------------------------------
# Confluent wire-format serialization
# ---------------------------------------------------------------------------

def serialize(schema_id: int, schema: dict, record: dict) -> bytes:
    """Encode a record as: 0x00 + schema_id (4 bytes BE) + avro payload."""
    parsed = fastavro.parse_schema(schema)
    buf    = BytesIO()
    fastavro.schemaless_writer(buf, parsed, record)
    return struct.pack("B", 0x00) + struct.pack(">I", schema_id) + buf.getvalue()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Produce mixed Avro messages to Kafka")
    parser.add_argument("--broker",   default="localhost:9092",       help="Kafka broker")
    parser.add_argument("--registry", default="http://localhost:8081", help="Schema Registry URL")
    parser.add_argument("--topic",    default="mixed-events",          help="Target topic")
    parser.add_argument("--count",    type=int, default=10,            help="Messages per schema type")
    parser.add_argument("--delay",    type=float, default=0.2,         help="Seconds between messages")
    args = parser.parse_args()

    # Resolve schema IDs from registry
    print(f"Fetching schema IDs from {args.registry}...")
    schema_ids = {}
    for full_name in SCHEMAS:
        schema_ids[full_name] = get_schema_id(args.registry, full_name)
        print(f"  {full_name}  →  id={schema_ids[full_name]}")

    producer = Producer({
        "bootstrap.servers": args.broker,
        "linger.ms": 5,
    })

    def on_delivery(err, msg):
        if err:
            print(f"  [ERROR] delivery failed: {err}")
        else:
            print(f"  [OK]    {msg.topic()} [{msg.partition()}] offset={msg.offset()}")

    total = 0
    schema_names = list(SCHEMAS.keys())

    print(f"\nProducing {args.count} messages per schema type to '{args.topic}'...")
    for i in range(args.count):
        # Alternate between schema types, then randomise within each round
        for full_name in schema_names:
            schema    = SCHEMAS[full_name]
            schema_id = schema_ids[full_name]
            record    = GENERATORS[full_name]()
            payload   = serialize(schema_id, schema, record)

            print(f"  [{full_name}]  {record}")
            producer.produce(
                topic    = args.topic,
                value    = payload,
                key      = record.get("order_id") or record.get("user_id"),
                callback = on_delivery,
            )
            producer.poll(0)
            total += 1

        if args.delay > 0:
            time.sleep(args.delay)

    producer.flush()
    print(f"\nDone. Produced {total} messages total.")


if __name__ == "__main__":
    main()
