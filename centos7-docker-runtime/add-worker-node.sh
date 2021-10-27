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

# Install kubelet, kubeadm
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

yum install -y kubeadm-$K8S_VERSION kubelet-$K8S_VERSION kubectl-$K8S_VERSION --disableexcludes=kubernetes
systemctl enable kubelet
systemctl start kubelet

# sysctl
echo "--> STEP 04."
cat >>/etc/sysctl.d/k8s.conf<<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system >/dev/null 2>&1
fi

#########################################################################################
# SECTION 3: CONFIG
# join cluster
# curl -s http://$MASTER_IP/join-cluster.sh | bash
