#!/bin/bash

helm repo add timeplus https://install.timeplus.com/charts
helm repo update
helm search repo timeplus -l | head -n 3

VERSION=`helm search repo timeplus/timeplus-enterprise -l | awk 'NR==2 {print $2}'`

export NS=timeplus
kubectl create ns $NS

export RELEASE=timeplus

helm -n $NS install -f values.yaml $RELEASE timeplus/timeplus-enterprise --version $VERSION

kubectl get pods -n $NS
