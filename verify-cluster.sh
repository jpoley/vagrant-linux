#!/bin/bash
# Script to verify Kubernetes cluster is properly set up

echo "=== Verifying Kubernetes Cluster ==="
echo ""

echo "1. Checking node status..."
vagrant ssh k8s-control-plane -c "kubectl get nodes -o wide"
echo ""

echo "2. Checking if control-plane is untainted..."
vagrant ssh k8s-control-plane -c "kubectl describe node k8s-control-plane | grep -i taint"
echo ""

echo "3. Checking Calico CNI status..."
vagrant ssh k8s-control-plane -c "kubectl get pods -n kube-system -l k8s-app=calico-node"
echo ""

echo "4. Checking cluster info..."
vagrant ssh k8s-control-plane -c "kubectl cluster-info"
echo ""

echo "5. Checking all system pods..."
vagrant ssh k8s-control-plane -c "kubectl get pods -A"
echo ""

echo "=== Verification Complete ==="
