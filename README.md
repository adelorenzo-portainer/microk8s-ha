# Steps to create a HA microk8s cluster with NFS persistent volume and default storage class

### Assumptions & pre-reqs
* Have at least 5 nodes available for the microk8s kubernetes cluster:
	* 3 master nodes for HA
	* 2 worker nodes
* All nodes are running Ubuntu server (minimum 18.04 LTS) or linux distro with snapd installed
* `/etc/hosts` has been populated with the IP addtresses of all 5 nodes, e.g.:
```
#!/bin/bash
cat <<EOF >> /etc/hosts
192.168.10.20 microk8s00
192.168.10.21 microk8s01
192.168.10.22 microk8s02
192.168.10.23 microk8s03
192.168.10.24 microk8s04
192.168.10.25 microk8s05
192.168.10.26 microk8s06
192.168.10.27 microk8s07
192.168.10.28 microk8s08
192.168.10.29 microk8s09
EOF
```

### 1. Install microk8s & kubectl
```
sudo snap install microk8s --classic && sudo snap install kubectl --classic
```

### 2. Initialize the first Master node
```
sudo microk8s enable rbac dns metrics-server helm3
```

### 3. NFS persistent volume
#### 3.1 Install the CSI driver for NFS:
```
sudo microk8s helm3 repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts && sudo microk8s helm3 repo update
```

#### 3.2 Helm chart under the `kube-system` namespace with:
```
helm3 install csi-driver-nfs csi-driver-nfs/csi-driver-nfs \
    --namespace kube-system \
    --set kubeletDir=/var/snap/microk8s/common/var/lib/kubelet
```

#### 3.3 Create a StorageClass for NFS:
```
kubectl apply -f - <<EOY
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-csi
provisioner: nfs.csi.k8s.io
parameters:
  server: 192.168.10.8
  share: /srv/nfs
reclaimPolicy: Delete
volumeBindingMode: Immediate
mountOptions:
  - hard
  - nfsvers=4.1
EOY
```

#### 3.4 Patch the NFS StorageClass ad default:
```
kubectl patch storageclass nfs-csi -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### 4. Create the cluster
#### 4.1 add 2 additional master nodes for HA
Run the `microk8s add-node`.  The output should be similar to the one below:

```
From the node you wish to join to this cluster, run the following:
microk8s join 192.168.10.20:25000/71cb52eabe7b058456675522408988f9/16cdd80eba4e

Use the '--worker' flag to join a node as a worker not running the control plane, eg:
microk8s join 192.168.10.20:25000/71cb52eabe7b058456675522408988f9/16cdd80eba4e --worker

If the node you are adding is not reachable through the default interface you can use one of the following:
microk8s join 192.168.10.20:25000/71cb52eabe7b058456675522408988f9/16cdd80eba4e
```

Run the first option like the example `microk8s join 192.168.10.20:25000/71cb52eabe7b058456675522408988f9/16cdd80eba4e` on the other two master nodes. 

_**For each node a `microk8s add-node` has to be ran as the tokens last few minutes and have to be unique.**_

Check if HA has been enabled successfully by running `microk8s status` on any of the master nodes. The ouput should be similar to the one below:
```
microk8s is running
high-availability: yes
  datastore master nodes: 192.168.10.20:19001 192.168.10.21:19001 192.168.10.22:19001
  datastore standby nodes: none
addons:
  enabled:
    dns                  # (core) CoreDNS
    ha-cluster           # (core) Configure high availability on the current node
    helm3                # (core) Helm 3 - Kubernetes package manager
    metrics-server       # (core) K8s Metrics Server for API access to service metrics
    rbac                 # (core) Role-Based Access Control for authorisation
  disabled:
    community            # (core) The community addons repository
    dashboard            # (core) The Kubernetes dashboard
    gpu                  # (core) Automatic enablement of Nvidia CUDA
    helm                 # (core) Helm 2 - the package manager for Kubernetes
    host-access          # (core) Allow Pods connecting to Host services smoothly
    hostpath-storage     # (core) Storage class; allocates storage from host directory
    ingress              # (core) Ingress controller for external access
    mayastor             # (core) OpenEBS MayaStor
    metallb              # (core) Loadbalancer for your Kubernetes cluster
    prometheus           # (core) Prometheus operator for monitoring and logging
    registry             # (core) Private image registry exposed on localhost:32000
    storage              # (core) Alias to hostpath-storage add-on, deprecated
```

#### 4.2 add the two worker nodes:
Run the `microk8s add-node` just like for the HA nodes but in this cas select the option with the `--worker` flag on the two worker nodes.

```
From the node you wish to join to this cluster, run the following:
microk8s join 192.168.10.20:25000/71cb52eabe7b058456675522408988f9/16cdd80eba4e

Use the '--worker' flag to join a node as a worker not running the control plane, eg:
`microk8s join 192.168.10.20:25000/71cb52eabe7b058456675522408988f9/16cdd80eba4e --worker

If the node you are adding is not reachable through the default interface you can use one of the following:
microk8s join 192.168.10.20:25000/71cb52eabe7b058456675522408988f9/16cdd80eba4e
```

_**Once more for each worker node a `microk8s add-node` has to be ran on the master node as the tokens last few minutes and have to be unique.**_

### 5. Generate the `kubeconfig` file
Run `microk8s config` to generate the `kubeconfig` file for the cluster. You can copy the file or save in on the first master node as follows:
#### 5.1 create the .kube folder
```
mkdir -p $HOME/.kube
```

#### 5.2 Save the `kubeconfig` file in the `.kube` folder
```
microk8s config > $HOME/.kube
```

