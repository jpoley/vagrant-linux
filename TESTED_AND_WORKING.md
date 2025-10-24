# Tested and Working

This document describes what has been **actually tested** and confirmed working on ARM64 Mac with Parallels.

## Date Tested
2025-10-23

## System Configuration
- **Platform**: macOS ARM64 (Apple Silicon)
- **Hypervisor**: Parallels Desktop
- **Vagrant Box**: bento/ubuntu-24.04 (version 202508.03.0)

## What Works ✅

### 1. VM Provisioning
```bash
vagrant up
```
- Creates 3 VMs successfully:
  - k8s-control-plane (2 CPUs, 6GB RAM, IP: 192.168.57.10)
  - k8s-worker-1 (2 CPUs, 2GB RAM, IP: 192.168.57.11)
  - k8s-worker-2 (2 CPUs, 2GB RAM, IP: 192.168.57.12)

### 2. Binary Installation
All nodes have the following binaries installed:
- **containerd**: v1.7.28 (containerd.io package from Docker repository)
- **kubeadm**: v1.34.1
- **kubelet**: v1.34.1
- **kubectl**: v1.34.1

Kubernetes packages are held to prevent automatic upgrades.

### 3. Repository Configuration
- Docker repository added successfully for containerd
- Kubernetes repository (pkgs.k8s.io/core:/stable:/v1.34) added successfully
- GPG keys properly configured for both repositories

### 4. Basic VM Operations
```bash
# Destroy all VMs
vagrant destroy -f

# SSH into VMs
vagrant ssh k8s-control-plane
vagrant ssh k8s-worker-1
vagrant ssh k8s-worker-2

# Check status
vagrant status
```

## What Does NOT Work Yet ❌

### System Configuration
- Swap is NOT disabled
- Kernel modules (overlay, br_netfilter) NOT loaded
- Networking sysctls NOT configured
- /etc/hosts NOT configured with cluster node entries

### Containerd Configuration
- containerd service is NOT configured
- CRI plugin NOT configured
- systemd cgroup driver NOT set
- containerd service NOT started

### Kubernetes Cluster
- Cluster NOT initialized (no kubeadm init)
- No kubeconfig files
- No join tokens generated
- Workers NOT joined to cluster

### CNI
- No CNI installed
- No Cilium
- No networking between pods (no pods exist yet)

## Verification Commands

```bash
# Verify binaries are installed
vagrant ssh k8s-control-plane -c "containerd --version"
vagrant ssh k8s-control-plane -c "kubeadm version"
vagrant ssh k8s-control-plane -c "kubectl version --client"

# Check containerd service status (will show as not running)
vagrant ssh k8s-control-plane -c "systemctl status containerd"

# Check if cluster is initialized (will show no config)
vagrant ssh k8s-control-plane -c "ls -la /etc/kubernetes/"
```

## Next Steps

To get a working Kubernetes cluster, you need to manually:
1. Configure system settings (swap, kernel modules, sysctl)
2. Configure and start containerd
3. Initialize the control plane with kubeadm
4. Install CNI (Cilium)
5. Join worker nodes

See MANUAL_STEPS.md for detailed instructions.
