CREATE EXTERNAL STREAM test_kafka_es(raw string)
SETTINGS
    type='kafka',
    brokers='127.0.0.1:9092',
    topic='mytopic',
    skip_ssl_cert_check='true',
    security_protocol = 'SASL_PLAINTEXT',
    sasl_mechanism='SCRAM-SHA-256',
    username='admin_user',
    password='admin';

CREATE NAMED COLLECTION kafka_nc AS
    security_protocol='SASL_PLAINTEXT',
    sasl_mechanism='SCRAM-SHA-256',
    username='admin_user',
    password='admin';

CREATE EXTERNAL STREAM test_kafka_es_nc(raw string)
SETTINGS
    type='kafka',
    brokers='127.0.0.1:9092',
    topic='mytopic',
    skip_ssl_cert_check='true',
    named_collection='kafka_nc';

CREATE NAMED COLLECTION kafka_full_nc AS
    brokers='127.0.0.1:9092',
    skip_ssl_cert_check='true',
    security_protocol='SASL_PLAINTEXT',
    sasl_mechanism='SCRAM-SHA-256',
    username='admin_user',
    password='admin';

CREATE EXTERNAL STREAM test_kafka_es_full_nc(raw string)
SETTINGS
    type='kafka',
    topic='mytopic',
    named_collection='kafka_full_nc';
