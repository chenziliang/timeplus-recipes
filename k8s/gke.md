# Overview

This readme illustrate how to provision GKE cluster via `gcloud` command line

## Install `gcloud`

https://cloud.google.com/sdk/docs/install?hl=en

## Create the GKE Cluster

### Create Cluster 

Start with a control plane and no default node pool, so you have full control:
```
gcloud container clusters create my-gke-cluster \
  --region us-central1 \
  --no-enable-autoupgrade \
  --no-enable-autorepair \
  --num-nodes=1
```

- `--num-nodes=1` prevents GKE from creating the default pool.
- Drop the `--no-enable-*` flags if you want Google to auto-manage upgrades/repairs.

```
gcloud container clusters list --location=us-central1
```

``` 
gcloud container clusters get-credentials my-gke-cluster --location=us-central1  
```

### Add Node Pool (High CPU)

```
gcloud container node-pools create highcpu-pool \
  --cluster=my-gke-cluster \
  --region=us-central1-a \
  --machine-type=c4d-highcpu-32 \
  --node-locations=us-central1-a \
  --num-nodes=1 \
  --enable-autoscaling --min-nodes=1 --max-nodes=5
```

We may need check if the machine type is available in the region / zone 

```
gcloud compute machine-types list --filter="name~'c4d'"
```

### Add Node Pool (Standard)

```
gcloud container node-pools create standard-pool \
  --cluster=my-gke-cluster \
  --region=us-central1 \
  --machine-type=n2d-standard-8 \
  --node-locations=us-central1-a \
  --num-nodes=3 \
  --enable-autoscaling --min-nodes=3 --max-nodes=5
```

### Add Node Pool (Low CPU)

```
gcloud container node-pools create lowcpu-pool \
  --cluster=my-gke-cluster \
  --region=us-central1 \
  --node-locations=us-central1-a \
  --machine-type=c4d-standard-4 \
  --num-nodes=1
```

### Verify

List node pools:
```
gcloud container node-pools list --cluster=my-gke-cluster --region=us-central1
```

Check nodes inside the cluster:
```
kubectl get nodes --show-labels
```

### Use in Helm Charts

```
timeplusAppserver:
  enabled: true
  service:
    type: LoadBalancer
    annotations:
      networking.gke.io/load-balancer-type: "External"
    ports:
      - name: http
        port: 8000
        targetPort: 8000

  nodeSelector:
    cloud.google.com/gke-nodepool: lowcpu-pool

timeplusd:
  service:
    clusterIP: None

  replicas: 3

  storage:
    stream:
      className: premium-rwo
      size: 200Gi
      selector: false
      nativelogSubPath: ./nativelog
      metastoreSubPath: ./metastore
    history:
      className: premium-rwo
      size: 300Gi
      selector: false
      subPath: ./history
    log:
      enabled: true
      className: premium-rwo
      size: 40Gi
      selector: false
      subPath: ./log

  defaultAdminPassword: timeplusd@t+

  resources:
    limits:
      cpu: 8
      memory: 30Gi
    requests:
      cpu: 4
      memory: 15Gi

  nodeSelector:
    cloud.google.com/gke-nodepool: standard-pool

  computeNode:
    replicas: 1
    resources:
      limits:
        cpu: 32 
        memory: 60Gi
      requests:
        cpu: 16 
        memory: 30Gi

    nodeSelector:
      cloud.google.com/gke-nodepool: highcpu-pool
```

## References

https://cloud.google.com/sdk/docs/install?hl=en

https://gcloud-compute.com/intel.html

https://gcloud-compute.com/amd.html

