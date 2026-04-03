#!/usr/bin/env python3
"""
kafka_avro_fanout.py

Consumes Avro-encoded messages from a single Kafka topic (with Schema Registry),
detects the schema of each message, deserializes it, and fans out to per-schema
target topics.

Wire format expected (Confluent / Redpanda):
  byte 0    : magic byte 0x00
  bytes 1-4 : schema ID (big-endian uint32)
  bytes 5+  : Avro-encoded payload

Routing:
  By default the target topic is derived from the Avro schema's full name:
    "com.example.OrderEvent"  →  "com.example.OrderEvent"  (or a mapped name)
  A --topic-map argument accepts JSON like:
    '{"com.example.OrderEvent": "orders", "com.example.UserEvent": "users"}'
  Any schema not listed in the map falls back to the schema full name as the topic.

Usage:
  pip install confluent-kafka fastavro requests

  python kafka_avro_fanout.py \\
    --broker localhost:9092 \\
    --schema-registry http://localhost:18081 \\
    --source-topic mixed-events \\
    --group-id fanout-consumer \\
    [--topic-map '{"SchemaFullName": "target-topic"}'] \\
    [--auto-offset-reset earliest] \\
    [--dry-run]
"""

import argparse
import json
import logging
import signal
import struct
import sys
from io import BytesIO
from typing import Dict, Optional

import requests
import fastavro
from confluent_kafka import Consumer, Producer, KafkaError, KafkaException

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger(__name__)

MAGIC_BYTE = 0x00


# ---------------------------------------------------------------------------
# Schema Registry client (minimal, no extra SDK dependency)
# ---------------------------------------------------------------------------

class SchemaRegistryClient:
    def __init__(self, url: str):
        self.url = url.rstrip("/")
        self._cache: Dict[int, dict] = {}

    def get_schema(self, schema_id: int) -> dict:
        if schema_id in self._cache:
            return self._cache[schema_id]
        resp = requests.get(f"{self.url}/schemas/ids/{schema_id}", timeout=10)
        resp.raise_for_status()
        schema = json.loads(resp.json()["schema"])
        self._cache[schema_id] = schema
        return schema


# ---------------------------------------------------------------------------
# Avro deserialization helpers
# ---------------------------------------------------------------------------

def parse_message(raw: bytes, registry: SchemaRegistryClient):
    """
    Parse a Confluent-wire-format Avro message.
    Returns (schema_id, schema_dict, decoded_record).
    Raises ValueError on bad magic byte.
    """
    if len(raw) < 5:
        raise ValueError(f"Message too short ({len(raw)} bytes)")
    magic = raw[0]
    if magic != MAGIC_BYTE:
        raise ValueError(f"Bad magic byte: 0x{magic:02x} (expected 0x00)")
    schema_id = struct.unpack(">I", raw[1:5])[0]
    payload = raw[5:]

    schema = registry.get_schema(schema_id)
    parsed_schema = fastavro.parse_schema(schema)
    record = fastavro.schemaless_reader(BytesIO(payload), parsed_schema)
    return schema_id, schema, record


def schema_full_name(schema: dict) -> str:
    """Return 'namespace.name' or just 'name' for an Avro schema dict."""
    name = schema.get("name", "unknown")
    namespace = schema.get("namespace", "")
    return f"{namespace}.{name}" if namespace else name


# ---------------------------------------------------------------------------
# Re-serialization: produce the decoded record back as Avro on the target topic
# (keeps the same schema ID so downstream consumers can still use the registry)
# ---------------------------------------------------------------------------

def serialize_message(schema_id: int, schema: dict, record: dict) -> bytes:
    parsed_schema = fastavro.parse_schema(schema)
    buf = BytesIO()
    fastavro.schemaless_writer(buf, parsed_schema, record)
    payload = buf.getvalue()
    return struct.pack("B", MAGIC_BYTE) + struct.pack(">I", schema_id) + payload


# ---------------------------------------------------------------------------
# Delivery callback for producer
# ---------------------------------------------------------------------------

def delivery_report(err, msg):
    if err:
        log.error("Delivery failed for topic %s: %s", msg.topic(), err)
    else:
        log.debug("Delivered to %s [%d] offset %d", msg.topic(), msg.partition(), msg.offset())


# ---------------------------------------------------------------------------
# Main fan-out loop
# ---------------------------------------------------------------------------

def run(
    broker: str,
    schema_registry_url: str,
    source_topic: str,
    group_id: str,
    topic_map: Dict[str, str],
    auto_offset_reset: str,
    dry_run: bool,
):
    registry = SchemaRegistryClient(schema_registry_url)

    consumer = Consumer({
        "bootstrap.servers": broker,
        "group.id": group_id,
        "auto.offset.reset": auto_offset_reset,
        "enable.auto.commit": False,
    })

    producer = Producer({
        "bootstrap.servers": broker,
        "linger.ms": 5,
        "compression.type": "snappy",
    }) if not dry_run else None

    consumer.subscribe([source_topic])
    log.info("Subscribed to source topic: %s", source_topic)

    # Track per-schema stats
    stats: Dict[str, int] = {}

    # Graceful shutdown
    running = True

    def _stop(signum, frame):
        nonlocal running
        log.info("Shutdown signal received, stopping…")
        running = False

    signal.signal(signal.SIGINT, _stop)
    signal.signal(signal.SIGTERM, _stop)

    try:
        while running:
            msg = consumer.poll(timeout=1.0)
            if msg is None:
                continue
            if msg.error():
                if msg.error().code() == KafkaError._PARTITION_EOF:
                    continue
                raise KafkaException(msg.error())

            raw = msg.value()
            if raw is None:
                continue

            try:
                schema_id, schema, record = parse_message(raw, registry)
            except Exception as exc:
                log.warning("Skipping undecodable message (offset %d): %s", msg.offset(), exc)
                consumer.commit(message=msg)
                continue

            full_name = schema_full_name(schema)
            target_topic = topic_map.get(full_name, full_name)

            stats[full_name] = stats.get(full_name, 0) + 1

            if dry_run:
                log.info(
                    "[DRY-RUN] schema=%s  →  topic=%s  record=%s",
                    full_name, target_topic, record,
                )
            else:
                out_bytes = serialize_message(schema_id, schema, record)
                # Preserve key if present
                key = msg.key()
                producer.produce(
                    topic=target_topic,
                    value=out_bytes,
                    key=key,
                    callback=delivery_report,
                )
                producer.poll(0)

            consumer.commit(message=msg)

    finally:
        consumer.close()
        if producer:
            log.info("Flushing producer…")
            producer.flush()
        log.info("Fan-out stats (schema → messages routed): %s", stats)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Fan out Avro messages from one Kafka topic to per-schema target topics."
    )
    parser.add_argument("--broker", default="localhost:9092", help="Kafka bootstrap server(s)")
    parser.add_argument(
        "--schema-registry", default="http://localhost:8081",
        metavar="URL", help="Schema Registry base URL"
    )
    parser.add_argument("--source-topic", required=True, help="Source Kafka topic to consume from")
    parser.add_argument("--group-id", default="kafka-avro-fanout", help="Consumer group ID")
    parser.add_argument(
        "--topic-map",
        default="{}",
        metavar="JSON",
        help='JSON mapping of Avro full name → target topic, e.g. \'{"com.ex.Foo": "foo-topic"}\'',
    )
    parser.add_argument(
        "--auto-offset-reset", default="latest",
        choices=["earliest", "latest"],
        help="Where to start consuming if no committed offset exists",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Decode and log messages without producing to target topics",
    )
    parser.add_argument("--debug", action="store_true", help="Enable debug logging")

    args = parser.parse_args()

    if args.debug:
        logging.getLogger().setLevel(logging.DEBUG)

    try:
        topic_map: Dict[str, str] = json.loads(args.topic_map)
    except json.JSONDecodeError as exc:
        log.error("--topic-map is not valid JSON: %s", exc)
        sys.exit(1)

    log.info("Starting fan-out: source=%s  registry=%s  dry_run=%s",
             args.source_topic, args.schema_registry, args.dry_run)
    if topic_map:
        log.info("Topic map: %s", topic_map)
    else:
        log.info("No explicit topic map — target topic = Avro schema full name")

    run(
        broker=args.broker,
        schema_registry_url=args.schema_registry,
        source_topic=args.source_topic,
        group_id=args.group_id,
        topic_map=topic_map,
        auto_offset_reset=args.auto_offset_reset,
        dry_run=args.dry_run,
    )


if __name__ == "__main__":
    main()
