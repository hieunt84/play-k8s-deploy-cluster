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

# "--> STEP 01. check requirements"
echo "--> STEP 01. check requirements"

# Tắt swap: Nên tắt swap để kubelet hoạt động ổn định.
echo "[TASK 1] Turn off swap"
sed -i '/swap/d' /etc/fstab
swapoff -a

echo "[TASK 2] Enable and Load Kernel modules"
cat >>/etc/modules-load.d/containerd.conf<<EOF
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

echo "[TASK 3] Add Kernel settings"
cat >>/etc/sysctl.d/kubernetes.conf<<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system >/dev/null 2>&1

# "--> STEP 02. Install containerd runtime"
echo "--> STEP 02. Install containerd runtime"

# setup repo
sudo yum install -y yum-utils >/dev/null 2>&1
sudo yum-config-manager \
    --add-repo \
    https://download.docker.com/linux/centos/docker-ce.repo

yum update -y >/dev/null 2>&1
yum install -y containerd apt-transport-https >/dev/null 2>&1
sudo mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd >/dev/null 2>&1

# --> STEP 03. install Kubernetes components kubelet, kubeadm và kubectl
echo "--> STEP 03. install Kubernetes components"

cat >> /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kube*
EOF
yum update -y >/dev/null 2>&1

# yum install -y -q kubelet kubeadm kubectl --disableexcludes=kubernetes
yum install -y kubeadm-$K8S_VERSION kubelet-$K8S_VERSION kubectl-$K8S_VERSION --disableexcludes=kubernetes

systemctl enable kubelet
systemctl start kubelet

# "--> STEP 04. Install apache"
echo "--> STEP 04. Install apache"

yum install httpd -y >/dev/null 2>&1
systemctl enable httpd
systemctl start httpd

# "--> STEP 05. config cluster"
echo "--> STEP 05. config cluster"

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