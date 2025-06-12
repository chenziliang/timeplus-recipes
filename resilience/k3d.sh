#!/bin/bash

k3d cluster create local \
    --api-port 8080 \
    -p "8463:8463@loadbalancer" \
    -p "8000:8000@loadbalancer" \
    --servers 1 \
    --servers-memory 4G \
    --agents 4 \
    --agents-memory 8G 


export NS=timeplus
export RELEASE=timeplus
export VERSION=v7.0.4
helm -n $NS install -f timeplusd-helm.yaml $RELEASE timeplus/timeplus-enterprise --version $VERSION
