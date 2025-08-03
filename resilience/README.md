#!/bin/bash

# Launch k3d cluster

```
# Create local k3d cluster
k3d cluster create local \
    --api-port 8080 \
    -p "8463:8463@loadbalancer" \
    -p "8000:8000@loadbalancer" \
    --servers 1 \
    --servers-memory 4G \
    --agents 4 \
    --agents-memory 8G \
    -v /Users/k/demo:/var/lib/rancher/k3s/storage@all

# Validate the cluster
k3d cluster list
k3d node list 
```

# Install service pods like load balancers and timeplus enterprise cluster

```
export NS=timeplus
export RELEASE=timeplus
export VERSION=v7.0.13

kubectl create ns $NS

kubectl apply -f resilience/timeplusd/services.yaml --wait

helm install -n $NS -f resilience/timeplusd/timeplusd-helm.yaml $RELEASE timeplus/timeplus-enterprise --version $VERSION

kubectl wait --for=condition=Ready pods --all -n $NS --timeout=300s

## Logon Timeplus Console

Log on http://localhost:8000

## Check the cluster load balancer

```
watch -n 1 'timeplusd client --user test --password test1234 --query "select node_id(), now()"'  
```

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

# Unstall

```
helm -n $NS uninstall $RELEASE
```

# Upgrade if upgrade from existing cluster 
helm -n $NS upgrade -f resilience/timeplusd/timeplusd-helm.yaml $RELEASE timeplus/timeplus-enterprise

# Fix k3d kubeconfig issues

List current kube context

```
kubectl config get-contexts

kubectl config current-context
```

## If k3d kubeconfig is not merged to ~/.kube/config

Try 

```
k3d kubeconfig merge local --switch

k3d kubeconfig get local > kubeconfig-local.yaml
```

## kubectl can't talk to k8s API server

Change **https://host.docker.internal:8080** to **https://127.0.0.1:8080** in ~/.kube/config
OR add the following entry to /etc/hosts 

```
127.0.0.1 host.docker.internal 
```
