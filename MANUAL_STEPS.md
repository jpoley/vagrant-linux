# Manual Kubernetes Cluster Initialization Steps

This guide provides step-by-step commands for manually initializing the Kubernetes cluster after VMs are provisioned with ONLY binaries.

## Prerequisites

After running `vagrant up`, all VMs will have:
- ✅ Ubuntu 24.04
- ✅ containerd binary installed
- ✅ kubeadm, kubelet, kubectl 1.34.1 binaries installed
- ❌ NO configuration applied - you must run everything manually

## Initialization Order

### 1. Verify VM Provisioning (Run on Host)

```bash
# Check all VMs are running
vagrant status

# Should show all 3 VMs as "running"
```

### 2. System Configuration (Run on EACH VM)

```bash
# SSH into each VM
vagrant ssh k8s-control-plane  # or k8s-worker-1, k8s-worker-2

# Become root
sudo -i

# Disable swap
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# Load kernel modules
modprobe overlay
modprobe br_netfilter

# Make kernel modules persistent
cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

# Configure sysctl
cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply sysctl settings
sysctl --system

# Configure /etc/hosts
cat <<EOF >> /etc/hosts
192.168.57.10 k8s-control-plane
192.168.57.11 k8s-worker-1
192.168.57.12 k8s-worker-2
EOF

# Configure containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# Enable systemd cgroup driver
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Start and enable containerd
systemctl daemon-reload
systemctl enable --now containerd
systemctl status containerd

# Enable kubelet
systemctl enable kubelet
# Don't start it yet - it will fail until cluster is initialized

# Exit root and logout
exit
exit
```

### 3. Control Plane Initialization (Run on k8s-control-plane)

```bash
# SSH into control plane
vagrant ssh k8s-control-plane

# Become root
sudo -i

# Verify containerd is running
systemctl status containerd
# Should show "active (running)"

# Verify kubelet is loaded
systemctl status kubelet
# May show "activating" or error - this is normal before kubeadm init

# Initialize the cluster
kubeadm init \
  --apiserver-advertise-address=192.168.57.10 \
  --pod-network-cidr=10.244.0.0/16 \
  --kubernetes-version=1.34.1

# This will take 2-5 minutes
# Watch for "Your Kubernetes control-plane has initialized successfully!"
# SAVE the kubeadm join command that's printed at the end
```

### 3. Configure kubectl for vagrant user (Run on k8s-control-plane)

```bash
# Still as root, or switch to vagrant user:
exit  # exit root shell if needed
# Back as vagrant user

# Create .kube directory
mkdir -p $HOME/.kube

# Copy admin config
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Verify kubectl works
kubectl get nodes
# Should show k8s-control-plane with status "NotReady" (CNI not installed yet)
```

### 4. Install Calico CNI (Run on k8s-control-plane)

```bash
# Still as vagrant user on k8s-control-plane

# Download Calico manifest
curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml

# Apply Calico
kubectl apply -f calico.yaml

# Wait for Calico pods to be ready (may take 1-3 minutes)
kubectl wait --for=condition=Ready pods -l k8s-app=calico-node -n kube-system --timeout=300s

# Verify all Calico pods are running
kubectl get pods -n kube-system -l k8s-app=calico-node

# Check node is now Ready
kubectl get nodes
# Should show k8s-control-plane with status "Ready"
```

### 5. Untaint Control Plane (Optional - allows pod scheduling on control plane)

```bash
# Still as vagrant user on k8s-control-plane

# Remove NoSchedule taint
kubectl taint nodes k8s-control-plane node-role.kubernetes.io/control-plane:NoSchedule-

# Verify taint is removed
kubectl describe node k8s-control-plane | grep -i taint
# Should show "Taints: <none>"
```

### 6. Generate Join Command for Workers (Run on k8s-control-plane)

```bash
# Still as vagrant user on k8s-control-plane

# Generate new join command (in case you lost the original)
kubeadm token create --print-join-command

# Copy this entire command - you'll need it for each worker
```

### 7. Join Worker Node 1 (Run on k8s-worker-1)

```bash
# From host, SSH to worker-1
vagrant ssh k8s-worker-1

# Become root
sudo -i

# Verify containerd is running
systemctl status containerd

# Run the join command from step 6
# Example (use YOUR actual command):
kubeadm join 192.168.57.10:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>

# This should take 30-60 seconds
# Watch for "This node has joined the cluster"

# Exit back to host
exit
exit
```

### 8. Join Worker Node 2 (Run on k8s-worker-2)

```bash
# From host, SSH to worker-2
vagrant ssh k8s-worker-2

# Become root
sudo -i

# Verify containerd is running
systemctl status containerd

# Run the join command from step 6 (same command as worker-1)
kubeadm join 192.168.57.10:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>

# Exit back to host
exit
exit
```

### 9. Verify Cluster (Run on k8s-control-plane)

```bash
# SSH back to control plane
vagrant ssh k8s-control-plane

# Check all nodes are Ready
kubectl get nodes
# Should show:
# k8s-control-plane   Ready    control-plane   <age>   v1.34.1
# k8s-worker-1        Ready    <none>          <age>   v1.34.1
# k8s-worker-2        Ready    <none>          <age>   v1.34.1

# Check all system pods are running
kubectl get pods -n kube-system

# Check Calico is healthy
kubectl get pods -n kube-system -l k8s-app=calico-node
# All should show "Running" with 1/1 Ready
```

### 10. Test Cluster Functionality (Run on k8s-control-plane)

```bash
# Still on control plane as vagrant user

# Create test deployment
kubectl create deployment nginx --image=nginx:latest --replicas=3

# Wait for pods to be ready
kubectl wait --for=condition=Ready pods -l app=nginx --timeout=120s

# Check pods are distributed across nodes
kubectl get pods -o wide -l app=nginx

# Expose deployment
kubectl expose deployment nginx --port=80 --type=NodePort

# Get service details
kubectl get svc nginx

# Test from any node (replace <NodePort> with actual port from above)
curl http://192.168.57.10:<NodePort>
curl http://192.168.57.11:<NodePort>
curl http://192.168.57.12:<NodePort>

# Cleanup test deployment
kubectl delete deployment nginx
kubectl delete service nginx
```

## Troubleshooting Commands

### Check containerd

```bash
sudo systemctl status containerd
sudo journalctl -u containerd -f  # Follow logs
sudo crictl ps  # List running containers
```

### Check kubelet

```bash
sudo systemctl status kubelet
sudo journalctl -u kubelet -f  # Follow logs
```

### Check kubeadm init logs

```bash
# If kubeadm init fails, check:
sudo journalctl -xeu kubelet
sudo kubeadm reset  # If you need to retry init
```

### Check Calico

```bash
kubectl logs -n kube-system -l k8s-app=calico-node
kubectl describe pods -n kube-system -l k8s-app=calico-node
```

### Check cluster health

```bash
kubectl get componentstatuses
kubectl get pods -n kube-system
kubectl cluster-info
```

### Reset a node (if needed)

```bash
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d
sudo rm -rf $HOME/.kube
# Then re-run initialization or join command
```

## Files Created During Manual Steps

These files/directories are created during manual initialization:

### On Control Plane:
- `/etc/kubernetes/` - Kubernetes configuration files
  - `admin.conf` - Admin kubeconfig
  - `kubelet.conf` - Kubelet configuration
  - `controller-manager.conf` - Controller manager config
  - `scheduler.conf` - Scheduler config
  - `manifests/` - Static pod manifests
  - `pki/` - Certificates and keys
- `/home/vagrant/.kube/config` - User kubeconfig
- `/var/lib/kubelet/` - Kubelet runtime data
- `/var/lib/etcd/` - etcd database

### On Worker Nodes:
- `/etc/kubernetes/kubelet.conf` - Kubelet configuration
- `/etc/kubernetes/pki/` - Node certificates
- `/var/lib/kubelet/` - Kubelet runtime data

## Automated Provisioning (To Re-enable)

To go back to automatic provisioning, uncomment the sections in `Vagrantfile` starting at line 69.

## VirtualBox Stability Notes

If you experience VirtualBox "guru meditation" crashes during kubeadm init:
- Try running kubeadm init with `--v=5` for verbose logging
- Check VirtualBox VM logs in `~/VirtualBox VMs/k8s-control-plane/Logs/`
- Consider reducing control-plane memory or CPU
- VirtualBox 7.1.4 on Apple Silicon M2 has known stability issues with Kubernetes
- Alternative: Use Parallels, VMware Fusion, UTM, or cloud-based VMs
