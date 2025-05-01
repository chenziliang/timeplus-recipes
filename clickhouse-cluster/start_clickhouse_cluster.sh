#!/bin/bash

./programs/clickhouse server --config ./clickhouse-config/cluster/config-1.xml &
./programs/clickhouse server --config ./clickhouse-config/cluster/config-2.xml &
./programs/clickhouse server --config ./clickhouse-config/cluster/config-3.xml &