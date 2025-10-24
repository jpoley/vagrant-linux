# Vagrant Kubernetes Cluster for Linux (VirtualBox)

**3-Node Kubernetes 1.34.1 Cluster** with automated provisioning using Vagrant, VirtualBox, and Ansible.

## 📋 Overview

- **Kubernetes Version**: 1.34.1
- **Cluster**: 1 control-plane + 2 workers
- **Container Runtime**: containerd 1.7.28
- **CNI**: Calico
- **Base OS**: Ubuntu 24.04
- **Hypervisor**: VirtualBox (for Linux x86_64/amd64)

## ⚠️ CURRENT STATUS: FULLY AUTOMATED PROVISIONING

This project includes **complete automated provisioning**. Running `vagrant up` will:
- ✅ Install and configure containerd runtime
- ✅ Install Kubernetes binaries (kubelet, kubeadm, kubectl)
- ✅ Initialize the control plane with kubeadm
- ✅ Install Calico CNI
- ✅ Join worker nodes to the cluster
- ✅ Untaint control plane for workload scheduling

The cluster will be **fully functional** after provisioning completes.

## Prerequisites

- **Linux system** with x86_64/amd64 architecture
- **VirtualBox** 7.0+ (for Linux)
- **Vagrant** 2.4.0 or later
- **Ansible** 2.15.0 or later
- At least **10 GB RAM** available (cluster uses ~10 GB total)
- At least **30 GB disk space**

## 🎯 Quick Start

### Step 1: Setup Host Dependencies

Run the automated setup script to check and install Vagrant, VirtualBox, and Ansible:

```bash
./setup-host.sh
```

This script will:
- ✅ Check for required tools (Vagrant, VirtualBox, Ansible)
- ✅ Install missing tools or update outdated versions
- ✅ Add your user to the `vboxusers` group if needed
- ✅ Verify minimum version requirements

**⚠️ IMPORTANT**: If you were just added to the `vboxusers` group, you **MUST log out and log back in** before continuing.

### Step 2: Switch to VirtualBox Hypervisor

Linux systems often have KVM (Kernel Virtual Machine) running by default, which conflicts with VirtualBox. Switch to VirtualBox mode:

```bash
./switch-to-virtualbox.sh
```

This script will:
- ✅ Stop KVM services (libvirtd, virtlogd, virtlockd)
- ✅ Unload KVM kernel modules (kvm_intel/kvm_amd, kvm)
- ✅ Load VirtualBox kernel modules (vboxdrv, vboxnetflt, vboxnetadp)
- ✅ Verify VirtualBox is functional

### Step 3: Start the Kubernetes Cluster

```bash
vagrant up
```

This will:
1. Download the Ubuntu 24.04 Vagrant box (first time only)
2. Create 3 VMs (k8s-control-plane, k8s-worker-1, k8s-worker-2)
3. Run Ansible provisioning (all automated)

**Expected time**: 15-20 minutes (depending on your internet speed and system)

### Step 4: Verify the Cluster

```bash
./verify-cluster.sh
```

Or manually:

```bash
vagrant ssh k8s-control-plane -c "kubectl get nodes -o wide"
vagrant ssh k8s-control-plane -c "kubectl get pods -A"
```

## Cluster Configuration

| Component | Details |
|-----------|---------|
| **Kubernetes Version** | 1.34.1 |
| **Container Runtime** | containerd 1.7.28 |
| **CNI Plugin** | Calico 3.28.0 |
| **Base OS** | Ubuntu 24.04 LTS |
| **Control Plane IP** | 192.168.57.10 |
| **Worker 1 IP** | 192.168.57.11 |
| **Worker 2 IP** | 192.168.57.12 |
| **Pod Network CIDR** | 10.244.0.0/16 |

### Node Resources

- **Control Plane**: 2 CPU, 6144 MB RAM
- **Worker 1**: 2 CPU, 2048 MB RAM
- **Worker 2**: 2 CPU, 2048 MB RAM

## 🔄 Switching Between KVM and VirtualBox

This repository includes scripts to easily switch between hypervisors without conflicts.

### Switch to VirtualBox (for Kubernetes cluster)

```bash
./switch-to-virtualbox.sh
```

Use this before running `vagrant up` or when you want to use VirtualBox VMs.

### Switch to KVM (for Slicer or other KVM applications)

```bash
./switch-to-kvm.sh
```

Use this when you need KVM for other applications.

**Important Notes**:
- Always shut down running VMs before switching hypervisors
- Use `vagrant halt` to stop VirtualBox VMs before switching to KVM
- Use `virsh list --all` to check for running KVM VMs before switching to VirtualBox
- Both hypervisors cannot be active simultaneously

## 📚 Common Commands

### Cluster Management

```bash
# Start all nodes
vagrant up

# Start specific node
vagrant up k8s-control-plane
vagrant up k8s-worker-1
vagrant up k8s-worker-2

# Stop the cluster
vagrant halt

# Restart with re-provisioning
vagrant reload --provision

# Destroy the cluster
vagrant destroy -f

# Check cluster status
vagrant status
```

### SSH Access

```bash
# SSH into nodes
vagrant ssh k8s-control-plane
vagrant ssh k8s-worker-1
vagrant ssh k8s-worker-2

# Run single command without interactive shell
vagrant ssh k8s-control-plane -c "kubectl get nodes"
```

### Kubernetes Operations

```bash
# From control plane node
vagrant ssh k8s-control-plane

# Inside control plane:
kubectl get nodes
kubectl get pods -A
kubectl get namespaces
kubectl cluster-info

# Deploy a test workload
kubectl create deployment nginx --image=nginx
kubectl get pods
```

## 📁 Project Structure

```
vagrant-linux/
├── Vagrantfile                      # VM definitions and provisioning orchestration
├── README.md                        # This file
├── CLAUDE.md                        # Project instructions for Claude Code
├── MANUAL_STEPS.md                  # Manual configuration steps (reference)
├── setup-host.sh                    # Install/check Vagrant, VirtualBox, Ansible
├── switch-to-virtualbox.sh          # Switch from KVM to VirtualBox
├── switch-to-kvm.sh                 # Switch from VirtualBox to KVM
├── verify-cluster.sh                # Verify cluster health
└── playbooks/
    ├── common.yml                   # System configuration for all nodes
    ├── binaries-only.yml            # Install Kubernetes binaries
    ├── containerd.yml               # Configure containerd runtime
    ├── control-plane.yml            # Initialize Kubernetes control plane
    ├── calico.yml                   # Install Calico CNI
    ├── cilium.yml                   # Install Cilium CNI (alternative, not used)
    ├── untaint.yml                  # Allow scheduling on control plane
    ├── workers.yml                  # Join workers to cluster
    └── k8s-join-command.sh          # Generated join command (created during provisioning)
```

## 🐛 Troubleshooting

### VirtualBox Won't Start VMs

**Error**: `VirtualBox can't operate in VMX root mode`

**Solution**: Switch to VirtualBox mode:

```bash
./switch-to-virtualbox.sh
```

### "User not in vboxusers group"

**Solution**: Add yourself and re-login:

```bash
sudo usermod -aG vboxusers $USER
# Log out and log back in
```

### Workers Won't Join

**Issue**: Join token expired (tokens last 24 hours)

**Solution**: Generate new token on control plane:

```bash
vagrant ssh k8s-control-plane
kubeadm token create --print-join-command
```

Copy the output to `playbooks/k8s-join-command.sh` and reprovision workers:

```bash
vagrant provision k8s-worker-1 --provision-with worker
vagrant provision k8s-worker-2 --provision-with worker
```

### Nodes Show "NotReady"

**Check 1**: Verify CNI is running:

```bash
vagrant ssh k8s-control-plane -c "kubectl get pods -n kube-system -l k8s-app=calico-node"
```

**Check 2**: Verify containerd is running:

```bash
vagrant ssh k8s-worker-1 -c "systemctl status containerd"
```

**Check 3**: Check kubelet logs:

```bash
vagrant ssh k8s-worker-1 -c "journalctl -u kubelet -f"
```

### Pods Stuck in "Pending"

**Check**: Node resources:

```bash
vagrant ssh k8s-control-plane -c "kubectl describe nodes"
```

**Solution**: Increase node memory/CPU in Vagrantfile and reload:

```bash
vagrant reload
```

### "Box 'bento/ubuntu-24.04' could not be found"

**Solution**: Check internet connection and retry:

```bash
vagrant box add bento/ubuntu-24.04 --provider virtualbox
```

### Clean Slate (Nuclear Option)

If everything is broken:

```bash
# Destroy everything
vagrant destroy -f

# Remove Vagrant boxes (optional)
vagrant box remove bento/ubuntu-24.04

# Clean VirtualBox VMs manually if needed
VBoxManage list vms
VBoxManage unregistervm <vm-name> --delete

# Start fresh
vagrant up
```

## Modifying the Cluster

### Change Kubernetes Version

1. Edit `Vagrantfile` and update `KUBERNETES_VERSION` variable
2. Rebuild: `vagrant destroy -f && vagrant up`

### Change Node Resources

1. Edit the `NODES` array in `Vagrantfile`
2. Modify `cpus` or `memory` values
3. Apply changes: `vagrant reload`

### Add More Workers

1. Add new node to `NODES` array in `Vagrantfile`
2. Add node to `/etc/hosts` section in `playbooks/common.yml`
3. Start the new node: `vagrant up <new-node-name>`

## Accessing the Cluster from Host

To use `kubectl` from your host machine:

```bash
# Copy kubeconfig from control plane
vagrant ssh k8s-control-plane -c "cat ~/.kube/config" > ~/.kube/vagrant-k8s-config

# Use the config
export KUBECONFIG=~/.kube/vagrant-k8s-config
kubectl get nodes
```

Note: You may need to update the server address in the config from `127.0.0.1:6443` to `192.168.57.10:6443`.

## 🔒 Security Notes

- This cluster is for **development/testing only**
- Control plane is untainted (allows workload scheduling)
- No network policies configured by default
- No RBAC restrictions beyond defaults
- Do not expose this cluster to the internet

## 🎓 Learning Resources

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Calico Documentation](https://docs.tigera.io/calico/latest/about/)
- [containerd Documentation](https://containerd.io/docs/)
- [Vagrant Documentation](https://www.vagrantup.com/docs)
- [Ansible Documentation](https://docs.ansible.com/)

## 🆘 Getting Help

If you encounter issues:

1. Check the [Troubleshooting](#-troubleshooting) section
2. Review logs: `vagrant ssh <node> -c "journalctl -u kubelet -f"`
3. Check Vagrant status: `vagrant status`
4. Verify hypervisor: `lsmod | grep -E "(kvm|vbox)"`
5. Check VirtualBox: `VBoxManage list vms`

## 📝 License

This project is provided as-is for educational and development purposes.

---

**Made with ❤️ for learning Kubernetes on Linux**
