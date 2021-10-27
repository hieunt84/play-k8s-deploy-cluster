#!/bin/bash

echo "[TASK 0] Declare variables"
CALICIO_VERISON="3.17"
POD_IP_RANGE="192.168.0.0/16"  # This IP Range is the default value of Calico
API_SERVER="172.20.10.110"

echo "[TASK 1] Pull required containers"
kubeadm config images pull >/dev/null 2>&1

echo "[TASK 2] Initialize Kubernetes Cluster"
kubeadm init --apiserver-advertise-address=$API_SERVER --pod-network-cidr=$POD_IP_RANGE >> /root/kubeinit.log 2>/dev/null

echo "[TASK 3] Deploy Calico network"
kubectl --kubeconfig=/etc/kubernetes/admin.conf create -f https://docs.projectcalico.org/v$CALICIO_VERISON/manifests/calico.yaml >/dev/null 2>&1

echo "[TASK 4] Generate and save cluster join command to /joincluster.sh"
kubeadm token create --print-join-command > /joincluster.sh 2>/dev/null

echo "[TASK 5] Setup kubectl for user root on Master Node"
export KUBECONFIG=/etc/kubernetes/admin.conf
echo 'export KUBECONFIG=/etc/kubernetes/admin.conf' >> ~/.bash_profile

echo "[TASK 6] Verify Setup Cluster"
kubectl get nodes

