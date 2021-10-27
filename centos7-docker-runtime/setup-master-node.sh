#!/bin/bash

##########################################################################################
# SECTION 1: PREPARE

# change root
sudo -i
sleep 1

# update system
# yum clean all
# yum -y update
# sleep 1

# config timezone
timedatectl set-timezone Asia/Ho_Chi_Minh

# disable SELINUX
setenforce 0 
sed -i 's/enforcing/disabled/g' /etc/selinux/config

# disable firewall
systemctl stop firewalld
systemctl disable firewalld

##########################################################################################
# SECTION 2: INSTALL

# TODO Make [pod network CIDR, K8s version, docker version, etc.] configurable
K8S_VERSION="1.20.11" # K8s is changed regularly. I just want to keep this script stable with v1.22
CALICIO_VERISON="3.17"
POD_IP_RANGE="192.168.0.0/16"  # This IP Range is the default value of Calico
API_SERVER="172.20.10.99"

# check requirements
echo "--> STEP 01. check requirements"
# Tắt swap: Nên tắt swap để kubelet hoạt động ổn định.
sed -i '/swap/d' /etc/fstab
swapoff -a

# install docker
echo "--> STEP 02. install Docker"
if [ ! -d /etc/systemd/system/docker.service.d ]; then

yum install -y yum-utils device-mapper-persistent-data lvm2
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
yum install -y docker-ce
mkdir /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
 "exec-opts": ["native.cgroupdriver=systemd"],
 "log-driver": "json-file",
 "log-opts": {
 "max-size": "100m"
 },
 "storage-driver": "overlay2",
 "storage-opts": [
   "overlay2.override_kernel_check=true"
 ]
}
EOF
mkdir -p /etc/systemd/system/docker.service.d

systemctl daemon-reload
systemctl restart docker
systemctl enable docker
fi

# Install kubelet, kubeadm và kubectl
echo "--> STEP 03. install Kubernetes components"
if [ ! -f /etc/yum.repos.d/kubernetes.repo ]; then
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kube*
EOF
yum update -y

# yum install -y -q kubelet kubeadm kubectl --disableexcludes=kubernetes
yum install -y kubeadm-$K8S_VERSION kubelet-$K8S_VERSION kubectl-$K8S_VERSION --disableexcludes=kubernetes

systemctl enable kubelet
systemctl start kubelet

# sysctl
cat >>/etc/sysctl.d/k8s.conf<<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system >/dev/null 2>&1

fi

# Install apache
yum install httpd -y
systemctl enable httpd
systemctl start httpd

#########################################################################################
# SECTION 3: CONFIG K8S CLUSTER
echo "--> STEP 04. config cluster"
# Configure NetworkManager before attempting to use Calico networking.
if [ ! -f /etc/NetworkManager/conf.d/calico.conf ]; then
cat >>/etc/NetworkManager/conf.d/calico.conf<<EOF
[keyfile]
unmanaged-devices=interface-name:cali*;interface-name:tunl*
EOF
fi

# Init the cluster
kubeadm init --pod-network-cidr=$POD_IP_RANGE --apiserver-advertise-address=$API_SERVER | tee kubeadm-init.out

# Setup kubectl for user root on Master Node
export KUBECONFIG=/etc/kubernetes/admin.conf
echo 'export KUBECONFIG=/etc/kubernetes/admin.conf' >> ~/.bash_profile

# Install Calico network. Ref. https://docs.projectcalico.org/v3.17/getting-started/kubernetes/installation/calico
kubectl apply -f https://docs.projectcalico.org/v$CALICIO_VERISON/manifests/calico.yaml

# Đến đây Master Node của Kubernetes Cluster đã sẵn sàng,
# cho Worker Node tham gia (join) vào

# Save command to join cluster
sudo kubeadm token create --print-join-command > /var/www/html/join-cluster.sh

# copy config cluster
cp /etc/kubernetes/admin.conf /var/www/html/config
chmod 755 /var/www/html/config

# chúng ta có thể kiểm tra trạng thái của Master Node như sau:
kubectl get nodes



