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
MASTER_IP="172.20.10.99"

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

#########################################################################################
# SECTION 3: CONFIG
# join cluster
# curl -s http://$MASTER_IP/join-cluster.sh | bash
