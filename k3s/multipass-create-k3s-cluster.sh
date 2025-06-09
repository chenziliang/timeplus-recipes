#!/bin/bash
# https://github.com/canonical/multipass
# brew install --cask multipass

# A five node worker cluster
multipass launch --name k3s --cpus 2 --memory 4G --disk 20G 

for i in `seq 1 4`
do
  multipass launch --name k3s-worker-$i --cpus 3 --memory 8G --disk 20G 
done


multipass stop k3s 
multipass delete k3s 

for i in `seq 1 4`
do
  multipass stop k3s-worker-$i
  multipass delete k3s-worker-$i
done

multipass purge


# Install k3s master / control plane 
multipass shell k3s 
curl -sfL https://get.k3s.io | sh -

# Register k3s workers

# Get token & IP of k3s controller
token=`multipass exec k3s sudo cat /var/lib/rancher/k3s/server/node-token` 
ip=`multipass info k3s | rg "^IPv4:\s+([\d\.]+)" -or '$1'`

for i in `seq 1 4` 
do
    multipass shell k3s-worker-$i 
done

curl -sfL https://get.k3s.io | K3S_URL=https://$ip:6443 K3S_TOKEN="$token" sh -

# List k3s nodes
multipass exec k3s -- sudo kubectl get nodes

# Deploy timeplus cluster via helm chart

# brew install helm on k3s node

multipass shell k3s 
sudo snap install helm --classic


helm repo add timeplus https://install.timeplus.com/charts
helm repo update
helm search repo timeplus -l

export NS=timeplus
kubectl create ns $NS

vim values.yaml
```
timeplusd:
  replicas: 3
  storage:
    stream:
      className: local-path
      size: 20Gi
      # Keep this to be `null` if you are on Amazon EKS with EBS CSI controller.
      # Otherwise please carefully check your provisioner and set them properly.
      selector: false
      nativelogSubPath: ./nativelog
      metastoreSubPath: ./metastore
    history:
      className: local-path
      size: 50Gi
      selector: false 
      subPath: ./history
    log:
      # This log PV is optional. If you have log collect service enabled on your k8s cluster, you can set this to be false.
      # If log PV is disabled, the log file will be gone after pod restarts.
      enabled: true
      className: local-path
      size: 10Gi
      selector: false 
      subPath: ./log
  defaultAdminPassword: timeplusd@t+
  resources:
    limits:
      cpu: "3"
      memory: "7Gi"
    requests:
      cpu: "2"
      memory: "6Gi"
```

sudo chmod 666 /etc/rancher/k3s/k3s.yaml
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

export RELEASE=timeplus
helm -n $NS install -f values.yaml $RELEASE timeplus/timeplus-enterprise

kubectl port-forward --address 0.0.0.0 svc/timeplus-appserver -n timeplus 8000:8000

multipass list # To get the node ipaddress and the logon Timepus UI by using that address

kubectl delete pod timeplusd-0 -n timeplus
kubectl logs -f timeplusd-0 -n timeplus

# Copy pods logs to k3s node

mkdir cluster-log && cd cluster-log

for i in `seq 0 2`
do
  kubectl cp timeplus/timeplusd-$i:/var/log/timeplusd-server/ timeplusd-server-$i
done

# Copy logs from k3s node to host 
multipass transfer -r k3s:/home/ubuntu/cluster-log .


helm --kubeconfig /etc/rancher/k3s/k3s.yaml -n $NS uninstall $RELEASE