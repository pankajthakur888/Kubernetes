# Kubernetes
Kubernetes is an open source system for managing containerized applications across multiple hosts. It provides basic mechanisms for deployment, maintenance, and scaling of applications.  Kubernetes builds upon a decade and a half of experience at Google running production workloads at scale using a system called Borg, combined with best-of-breed ideas and practices from the community.  Kubernetes is hosted by the Cloud Native Computing Foundation (CNCF). If your company wants to help shape the evolution of technologies that are container-packaged, dynamically scheduled, and microservices-oriented, consider joining the CNCF. For details about who's involved and how Kubernetes plays a role, read the CNCF
Kubernetes Installation on Ubuntu 20.04
Get the detailed information about the installation from the below-mentioned websites of Docker and Kubernetes.

Docker

Kubernetes

Set up the Docker and Kubernetes repositories:
Download the GPG key for docker

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
Add the docker repository

# Docker has release the repository for Ubuntu 20.04 Focal LTS.
# we can get the latest release versions from https://docs.docker.com

sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
Add the GPG key for kubernetes

curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
Add the kubernetes repository

Check for the latest release in https://packages.cloud.google.com/apt/dists

cat << EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
Update the repository

# Update the repositiries
sudo apt-get update
Install Docker and Kubernetes packages.

Note that if you want to use a newer version of Kubernetes, change the version installed for kubelet, kubeadm, and kubectl and be sure that all three use the same version. These version should support the Docker CE version.

# Use the same versions to avoid issues with the installation.
sudo apt-get install -y docker-ce=5:19.03.11~3-0~ubuntu-$(lsb_release -cs) kubelet=1.18.2-00 kubeadm=1.18.2-00 kubectl=1.18.2-00
To hold the versions so that the versions will get accidently upgraded.

sudo apt-mark hold docker-ce kubelet kubeadm kubectl
Enable the iptables bridge

#Set a value in the sysctl file , to allow proper network settings for Kubernetes on all the servers.
echo "net.bridge.bridge-nf-call-iptables=1" | sudo tee -a /etc/sysctl.conf

#To make the changes to take immediate effect for the iptables
sudo sysctl -p
On the Kube master server
Initialize the cluster by passing the cidr value and the value will depend on the type of network CLI you choose.

Use either Flannel or Calico

# For flannel network
# Copy your join command and keep it safe.
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

# Copy your join command and keep it safe.
# Below is a sample
kubeadm join 10.128.0.2:6443 --token swi0ci.jq9l75eg8lvpxz6g --discovery-token-ca-cert-hash sha256:2c3cdfa898334b0dfc0f73bbccb998d03f61252ee50f0405c85ba735ff90b4d1
# For Calico network
# Make sure to copy the join command
sudo kubeadm init --pod-network-cidr=192.168.0.0/16

# Copy your join command and keep it safe.
# Below is a sample
kubeadm join 10.128.0.2:6443 --token swi0ci.jq9l75eg8lvpxz6g --discovery-token-ca-cert-hash sha256:2c3cdfa898334b0dfc0f73bbccb998d03f61252ee50f0405c85ba735ff90b4d1
To start using the cluster with current user.

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
Set the flannel networking

# Use this if you have initialised the cluster with Flannel network add on.
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
To set up the Calico network

# Use this if you have initialised the cluster with Calico network add on.
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
Check the nodes

# Check the status on the master node.
kubectl get nodes
On each of Kube node server
Joining the node to the cluster:

sudo kubeadm join $controller_private_ip:6443 --token $token --discovery-token-ca-cert-hash $hash
TIP

If the joining code is lost, it can retrieve using below command

kubeadm token create --print-join-command
About
Install Kubernetes on Ubuntu 20.04

Resources
 Readme
Releases
No releases published
Packages
No packages published
Languages
Vim script
100.0%
