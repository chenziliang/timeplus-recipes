#!/bin/bash

docker run --pull=always --name mysql --rm \
    -v /Users/k/code/docker-volume/mysql:/var/lib/mysql \
    -p 3306:3306 \
    -e MYSQL_ROOT_PASSWORD=my \
    mysql:latest
