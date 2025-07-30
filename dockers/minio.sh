#!/bin/bash

docker run -p 9000:9000 -p 9001:9001 --name minio \
  -e "MINIO_ROOT_USER=minioadmin" \
  -e "MINIO_ROOT_PASSWORD=minioadmin" \
  -v /Users/k/code/docker-volume/minio/data:/data \
  quay.io/minio/minio server /data --console-address ":9001"
