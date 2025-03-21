#!/bin/bash
# https://github.com/canonical/multipass
# brew install --cask multipass

# A five node worker cluster
multipass launch --name k3s --cpu 2 --memory 4G --disk 20G 
multipass launch --name k3s-worker-1 --cpus 3 --memory 4G --disk 20G 
multipass launch --name k3s-worker-2 --cpus 3 --memory 4G --disk 20G 
multipass launch --name k3s-worker-3 --cpus 3 --memory 4G --disk 20G 
multipass launch --name k3s-worker-4 --cpus 3 --memory 4G --disk 20G 
multipass launch --name k3s-worker-5 --cpus 3 --memory 4G --disk 20G 


# Install k3s master / control plane 
multipass shell k3s

curl -sfL https://get.k3s.io | sh -

# Register k3s workers

# Get token & IP of k3s controller
token=`multipass exec k3s sudo cat /var/lib/rancher/k3s/server/node-token` 
ip=`multipass info k3s | rg "^IPv4:\s+([\d\.]+)" -or '$1'`


for i in `seq 1 5` 
do
    multipass shell k3s-worker-$i
    curl -sfL https://get.k3s.io | K3S_URL=https://$ip:6443 K3S_TOKEN="$token" sh -
done

# List k3s nodes
multipass exec k3s -- sudo kubectl get nodes

# Deploy timeplus cluster via helm chart

# brew install helm

multipass shell k3s -- sudo snap install helm --classic



```
timeplusd:
  replicas: 3
  storage:
    stream:
      className: local-path
      size: 20Gi
      # Keep this to be `null` if you are on Amazon EKS with EBS CSI controller.
      # Otherwise please carefully check your provisioner and set them properly.
      selector: null
    history:
      className: local-path
      size: 50Gi
      selector: null
    log:
      # This log PV is optional. If you have log collect service enabled on your k8s cluster, you can set this to be false.
      # If log PV is disabled, the log file will be gone after pod restarts.
      enabled: true
      className: local-path
      size: 10Gi
      selector: null
  defaultAdminPassword: timeplusd@t+
  resources:
    limits:
      cpu: "3"
      memory: "5Gi"
    requests:
      cpu: "2"
      memory: "4Gi"
```

sudo chmod 666 /etc/rancher/k3s/k3s.yaml
 
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

kubectl port-forward --address 0.0.0.0 svc/timeplus-appserver -n timeplus 8000:8000
