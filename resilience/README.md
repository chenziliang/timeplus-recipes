#!/bin/bash

# Launch k3d cluster

```
k3d cluster create local \
    --api-port 8080 \
    -p "8463:8463@loadbalancer" \
    -p "8000:8000@loadbalancer" \
    --servers 1 \
    --servers-memory 4G \
    --agents 4 \
    --agents-memory 8G 
```

# Install service pods like load balancers and timeplus enterprise cluster

```
export NS=timeplus
export RELEASE=timeplus
export VERSION=v7.0.4

kubectl create ns $NS

kubectl apply -f resilience/chaos_testing/timeplusd/services.yaml --wait

helm -n $NS install -f timeplusd-helm.yaml $RELEASE timeplus/timeplus-enterprise --version $VERSION

kubectl wait --for=condition=Ready pods --all -n timeplus --timeout=300s

# Check the cluster load balancer
watch -n 1 'timeplusd client --user test --password test1234 --query "select node_id(), now()"'  

```

# Logon Timeplus Console
Log on http://localhost:8000

# Chaos Mesh

```
helm repo add chaos-mesh https://charts.chaos-mesh.org

kubectl create ns chaos-mesh

helm install chaos-mesh chaos-mesh/chaos-mesh \
-n=chaos-mesh \
--set chaosDaemon.runtime=containerd \
--set chaosDaemon.socketPath=/run/k3s/containerd/containerd.sock

kubectl get pods --namespace chaos-mesh -l app.kubernetes.io/instance=chaos-mesh 

kubectl wait --for=condition=Ready pods --all -n chaos-mesh --timeout=300s
```

# Run data loader to emulate ingestion

```
./cmd/dataloader --config config.yml   
```

# Chaos experiments

## Pod failure

Show cluster overview in UI

```
kubectl apply -f resilience/chaos_testing/pod_failure.yaml

kubectl delete -f resilience/chaos_testing/pod_failure.yaml
```

## Pod kill

```
kubectl apply -f resilience/chaos_testing/pod_kill.yaml

kubectl delete -f resilience/chaos_testing/pod_kill.yaml
```

## Network partition

```
kubectl apply -f resilience/chaos_testing/network_partition.yaml

kubectl delete -f resilience/chaos_testing/network_partition.yaml
```

## Network packet corruption 

```
kubectl apply -f resilience/chaos_testing/network_packet_corruption.yaml

kubectl delete -f resilience/chaos_testing/network_packet_corruption.yaml
```

## Network packet loss

```
kubectl apply -f resilience/chaos_testing/network_packet_loss.yaml

kubectl delete -f resilience/chaos_testing/network_packet_loss.yaml
```

## Network bandwidth

```
kubectl apply -f resilience/chaos_testing/network_bandwidth.yaml

kubectl delete -f resilience/chaos_testing/network_bandwidth.yaml
```

## Network delay

```
kubectl apply -f resilience/chaos_testing/network_delay.yaml

kubectl delete -f resilience/chaos_testing/network_delay.yaml
```

## Time fault

```
kubectl apply -f resilience/chaos_testing/manifests/chaos_mesh/time_fault.yaml

kubectl delete -f resilience/chaos_testing/manifests/chaos_mesh/time_fault.yaml
```

## Disk fault -- not support yet
