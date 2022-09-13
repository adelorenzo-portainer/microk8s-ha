#!/bin/bash

echo "Deleting old ssh keys"
sleep .75

for i in {0..4}
do
  ssh-keygen -R 192.168.10.2$i
done


echo "Creating 5 VMs"
sleep .75

for i in {0..4}
do
  qm clone 9000 20$i --full 1 --name microk8s0$i --storage local
  qm set 20$i --ipconfig0 ip=192.168.10.2$i/24,gw=192.168.10.1 --nameserver 192.168.10.10
  qm start 20$i
done
sleep 20


echo "Setting up 1st master node"
sleep .75
ssh ubuntu@192.168.10.20 -o StrictHostKeyChecking=no 'sudo snap install microk8s --classic && sudo snap install kubectl --classic'
ssh ubuntu@192.168.10.20 -o StrictHostKeyChecking=no 'mkdir -p /home/ubuntu/.kube'
ssh ubuntu@192.168.10.20 -o StrictHostKeyChecking=no 'sudo microk8s config > /home/ubuntu/.kube/config'
ssh ubuntu@192.168.10.20 -o StrictHostKeyChecking=no 'sudo microk8s enable rbac dns metrics-server helm3'
ssh ubuntu@192.168.10.20 -o StrictHostKeyChecking=no 'sudo microk8s helm3 repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts && sudo microk8s helm3 repo update'
ssh ubuntu@192.168.10.20 -o StrictHostKeyChecking=no 'sudo microk8s helm3 install csi-driver-nfs csi-driver-nfs/csi-driver-nfs --namespace kube-system  --set kubeletDir=/var/snap/microk8s/common/var/lib/kubelet'
ssh ubuntu@192.168.10.20 -o StrictHostKeyChecking=no "curl http://192.168.10.10/sc_nfs.sh | sudo bash -"


echo "Adding Portainer Agent"
sleep .75
ssh ubuntu@192.168.10.20 -o StrictHostKeyChecking=no "curl -L https://downloads.portainer.io/ee2-15/portainer-agent-k8s-nodeport.yaml -o portainer-agent-k8s.yaml; sudo kubectl apply -f portainer-agent-k8s.yaml"


echo "Installing NFS client & tmux"
sleep .75
for i in {0..4}
do
  ssh ubuntu@192.168.10.2$i -o StrictHostKeyChecking=no 'sudo apt -y install nfs-common tmux'
done


echo "Adding nodes to hosts file"
sleep .75
for i in {0..4}
do
  ssh ubuntu@192.168.10.2$i -o StrictHostKeyChecking=no "curl http://192.168.10.10/microk8s_hosts_rockstar.sh | sudo bash -"
done


echo "Installing microk8s on other nodes"
sleep .75
for i in {1..2}
do
  ssh ubuntu@192.168.10.2$i -o StrictHostKeyChecking=no 'sudo snap install microk8s --classic'
done

for i in {3..4}
do
  ssh ubuntu@192.168.10.2$i -o StrictHostKeyChecking=no 'tmux new -d sudo snap install microk8s --classic'
done


echo "Enabling HA on microk8s"
sleep .75
for i in {1..2}
do
  microk8s_add_node=`ssh ubuntu@192.168.10.20 -o StrictHostKeyChecking=no "sudo microk8s add-node" | tail -1`
  ssh ubuntu@192.168.10.2$i -o StrictHostKeyChecking=no "sudo $microk8s_add_node"
done


echo "Adding microk8s cluster to Portainer"
sleep .75

while true
do
pod_state=`ssh ubuntu@192.168.10.20 -o StrictHostKeyChecking=no "sudo kubectl get pod -n portainer  | tail -1"`
agent_state=`echo $pod_state | awk '{ print $3 }'`
if [ "$agent_state" != "Running" ]; then
        echo -ne '⚡ Portainer Agent Not Running yet\r'
else
        break
fi
sleep 1
done

sleep 15

jwt=`http --verify=no POST https://rockstar.the-edge.cloud/api/auth Username="rockstar" Password="portainer1234" | jq '.jwt' | sed 's/^.//' | sed 's/.$//'`
http --verify=no --form POST https://rockstar.the-edge.cloud/api/endpoints "Authorization: Bearer $jwt" Name="microk8s kubernetes" URL="tcp://192.168.10.20:30778" EndpointCreationType=2 TLS="true" TLSSkipVerify="true" TLSSkipClientVerify="true"


echo "Adding worker nodes"
sleep .75
for i in {3..4}
do
  microk8s_add_node=`ssh ubuntu@192.168.10.20 -o StrictHostKeyChecking=no "sudo microk8s add-node | grep worker" | tail -1`
  ssh ubuntu@192.168.10.2$i -o StrictHostKeyChecking=no "tmux new -d sudo $microk8s_add_node"
done

