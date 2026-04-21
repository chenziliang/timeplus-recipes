# Overview

This readme illustrates how to provision an EKS cluster via the `aws` CLI, then add additional node groups for different compute profiles.

## Install `aws` CLI

https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

Configure credentials once with `aws configure` (or `aws sso login`).

You will also need `kubectl`:

https://kubernetes.io/docs/tasks/tools/

## Create the EKS Cluster

Set some shared variables used throughout this guide:

```
export AWS_REGION=us-east-1
export CLUSTER_NAME=my-eks-cluster
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

### Prerequisite: IAM Roles

EKS requires two IAM roles: one for the control plane and one for worker nodes. Create them once per account.

Cluster role:
```
cat > cluster-trust.json <<'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"eks.amazonaws.com"},"Action":"sts:AssumeRole"}]}
EOF

aws iam create-role \
  --role-name eksClusterRole \
  --assume-role-policy-document file://cluster-trust.json

aws iam attach-role-policy \
  --role-name eksClusterRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
```

Node role:
```
cat > node-trust.json <<'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}
EOF

aws iam create-role \
  --role-name eksNodeRole \
  --assume-role-policy-document file://node-trust.json

for p in AmazonEKSWorkerNodePolicy AmazonEC2ContainerRegistryReadOnly AmazonEKS_CNI_Policy; do
  aws iam attach-role-policy \
    --role-name eksNodeRole \
    --policy-arn arn:aws:iam::aws:policy/$p
done
```

### Prerequisite: VPC and Subnets

Reuse the default VPC or create a dedicated one. To list subnets in the default VPC across AZs:

```
export VPC_ID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true \
  --query 'Vpcs[0].VpcId' --output text --region $AWS_REGION)

export SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters Name=vpc-id,Values=$VPC_ID \
  --query 'Subnets[*].SubnetId' --output text --region $AWS_REGION | tr '\t' ',')
```

EKS requires subnets in at least two AZs.

### Create Cluster

Start with the control plane (no node groups yet):

```
aws eks create-cluster \
  --name $CLUSTER_NAME \
  --region $AWS_REGION \
  --role-arn arn:aws:iam::$ACCOUNT_ID:role/eksClusterRole \
  --resources-vpc-config subnetIds=$SUBNET_IDS

aws eks wait cluster-active --name $CLUSTER_NAME --region $AWS_REGION
```

List and fetch kubeconfig:
```
aws eks list-clusters --region $AWS_REGION

aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION
```

### Add Node Group (Default / Standard)

Equivalent of the GKE default pool — AMD general purpose, 8 vCPU / 32 GiB:

```
aws eks create-nodegroup \
  --cluster-name $CLUSTER_NAME \
  --region $AWS_REGION \
  --nodegroup-name default-pool \
  --node-role arn:aws:iam::$ACCOUNT_ID:role/eksNodeRole \
  --subnets $(echo $SUBNET_IDS | tr ',' ' ') \
  --instance-types m6a.2xlarge \
  --scaling-config minSize=3,maxSize=5,desiredSize=3 \
  --ami-type AL2023_x86_64_STANDARD
```

### Add Node Group (High CPU)

Compute-optimized AMD, 32 vCPU:

```
aws eks create-nodegroup \
  --cluster-name $CLUSTER_NAME \
  --region $AWS_REGION \
  --nodegroup-name highcpu-pool \
  --node-role arn:aws:iam::$ACCOUNT_ID:role/eksNodeRole \
  --subnets $(echo $SUBNET_IDS | tr ',' ' ') \
  --instance-types c7a.8xlarge \
  --scaling-config minSize=1,maxSize=5,desiredSize=1 \
  --ami-type AL2023_x86_64_STANDARD
```

Check which instance types are offered in the region:

```
aws ec2 describe-instance-type-offerings \
  --location-type availability-zone \
  --filters Name=instance-type,Values='c7a.*' \
  --region $AWS_REGION
```

### Add Node Group (Low CPU)

Compute-optimized AMD, 4 vCPU — used for lightweight app-server workloads:

```
aws eks create-nodegroup \
  --cluster-name $CLUSTER_NAME \
  --region $AWS_REGION \
  --nodegroup-name lowcpu-pool \
  --node-role arn:aws:iam::$ACCOUNT_ID:role/eksNodeRole \
  --subnets $(echo $SUBNET_IDS | tr ',' ' ') \
  --instance-types c7a.xlarge \
  --scaling-config minSize=1,maxSize=1,desiredSize=1 \
  --ami-type AL2023_x86_64_STANDARD
```

### Verify

List node groups:
```
aws eks list-nodegroups --cluster-name $CLUSTER_NAME --region $AWS_REGION
```

Check nodes inside the cluster:
```
kubectl get nodes --show-labels
```

Managed node groups automatically carry the label `eks.amazonaws.com/nodegroup=<pool-name>`, which is what `nodeSelector` below uses.

### Install EBS CSI Driver (for PVCs)

EKS does not ship with persistent-volume support out of the box. Enable the EBS CSI add-on so the `gp3` StorageClass works:

```
aws eks create-addon \
  --cluster-name $CLUSTER_NAME \
  --region $AWS_REGION \
  --addon-name aws-ebs-csi-driver
```

A default `gp2` StorageClass already exists. To make `gp3` the default:

```
kubectl apply -f - <<'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOF
```

### Use in Helm Charts

```
timeplusAppserver:
  enabled: true
  service:
    type: LoadBalancer
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-type: "external"
      service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
      service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
    ports:
      - name: http
        port: 8000
        targetPort: 8000

  nodeSelector:
    eks.amazonaws.com/nodegroup: lowcpu-pool

timeplusd:
  service:
    clusterIP: None

  replicas: 3

  storage:
    stream:
      className: gp3
      size: 200Gi
      selector: false
      nativelogSubPath: ./nativelog
      metastoreSubPath: ./metastore
    history:
      className: gp3
      size: 300Gi
      selector: false
      subPath: ./history
    log:
      enabled: true
      className: gp3
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
    eks.amazonaws.com/nodegroup: default-pool

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
      eks.amazonaws.com/nodegroup: highcpu-pool
```

The external NLB annotations require the AWS Load Balancer Controller to be installed in the cluster. Install via Helm if not already present:

https://kubernetes-sigs.github.io/aws-load-balancer-controller/

## References

https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

https://docs.aws.amazon.com/eks/latest/userguide/create-cluster.html

https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html

https://aws.amazon.com/ec2/instance-types/
