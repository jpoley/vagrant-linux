# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Vagrant-based Kubernetes 1.34.1 cluster automation project using Ansible. It provisions a local 3-node cluster (1 control-plane + 2 workers) with containerd as the container runtime. Currently in **BINARIES ONLY MODE** - installs containerd, kubeadm, kubelet, kubectl without any cluster configuration.

## Cluster Configuration

- **Kubernetes Version**: 1.34.1 (defined in Vagrantfile)
- **Pod Network CIDR**: 10.244.0.0/16
- **Control Plane IP**: 192.168.57.10
- **Worker IPs**: 192.168.57.11, 192.168.57.12
- **Container Runtime**: containerd.io v1.7.28
- **Base Image**: bento/ubuntu-24.04
- **Hypervisor**: VirtualBox (for Linux)

## Current Status

**BINARIES ONLY MODE**: The current provisioning only installs binaries. NO configuration is applied:
- ✅ Installs: containerd, kubeadm, kubelet, kubectl
- ❌ Does NOT configure: swap, sysctl, kernel modules, /etc/hosts, containerd config, or start services
- ❌ Kubernetes cluster is NOT initialized
- ❌ CNI is NOT installed

All configuration must be done manually per MANUAL_STEPS.md

## Common Commands

### Cluster Management
```bash
# Start the entire cluster (all nodes)
vagrant up

# Start a specific node
vagrant up k8s-control-plane
vagrant up k8s-worker-1
vagrant up k8s-worker-2

# Halt/stop the cluster
vagrant halt

# Destroy the cluster
vagrant destroy -f

# SSH into nodes
vagrant ssh k8s-control-plane
vagrant ssh k8s-worker-1
vagrant ssh k8s-worker-2

# Reload with re-provisioning
vagrant reload --provision
```

### Cluster Verification
```bash
# Run the verification script
./verify-cluster.sh

# Manual verification from control plane
vagrant ssh k8s-control-plane -c "kubectl get nodes -o wide"
vagrant ssh k8s-control-plane -c "kubectl get pods -A"
vagrant ssh k8s-control-plane -c "cilium status"
```

### Re-provisioning
```bash
# Re-run specific provisioning steps
vagrant provision k8s-control-plane --provision-with ansible

# Force re-provisioning of all nodes
vagrant destroy -f && vagrant up
```

## Architecture

### Current Provisioning Flow

Currently only **binaries-only.yml** runs on all nodes:

1. **binaries-only.yml** - Binary installation only
   - Adds Docker repository and GPG key for containerd
   - Installs containerd.io package (v1.7.28)
   - Adds Kubernetes repository and GPG key
   - Installs kubelet, kubeadm, kubectl at version 1.34.1
   - Holds Kubernetes packages to prevent auto-updates
   - **Does NOT configure or start any services**

### Planned Provisioning Flow (Not Yet Implemented)

The full cluster provisioning would follow this sequence:

1. **common.yml** - System configuration for all nodes
   - Disable swap and configure kernel modules (overlay, br_netfilter)
   - Set up networking sysctls for Kubernetes
   - Add all cluster nodes to /etc/hosts

2. **containerd.yml** - Container runtime configuration
   - Configure CRI plugin and systemd cgroup driver
   - Critical: Set `SystemdCgroup = true` in config.toml
   - Enable and start containerd service

3. **control-plane.yml** - Control plane initialization
   - Run `kubeadm init` with `--skip-phases=addon/kube-proxy` (for Cilium)
   - Generate join command and save to `playbooks/k8s-join-command.sh`
   - Set up kubeconfig for both vagrant and root users

4. **cilium.yml** - CNI installation
   - Install Cilium CLI from GitHub releases
   - Deploy Cilium with `kubeProxyReplacement=true`
   - Wait for Cilium to become ready (5 min timeout)

5. **untaint.yml** - Allow control plane scheduling
   - Remove NoSchedule taint from control plane

6. **workers.yml** - Worker node join
   - Copy join command from playbooks directory
   - Join worker to the cluster using kubeadm join

### Key Design Decisions

- **VirtualBox provider**: For Linux systems (x86_64/amd64 architecture)
- **Binaries-first approach**: Install all required binaries, then configure manually
- **No kube-proxy** (planned): Will use `--skip-phases=addon/kube-proxy` because Cilium handles all kube-proxy functionality
- **Control plane scheduling** (planned): Control plane will be untainted to allow workload scheduling (suitable for dev/test)

### Important Files

- **Vagrantfile** - Node definitions, resource allocation, provisioning orchestration
- **playbooks/k8s-join-command.sh** - Generated during control-plane provisioning, contains the kubeadm join command with token
- **verify-cluster.sh** - Health check script for the cluster

## Modifying the Cluster

### Changing Kubernetes Version
1. Update `KUBERNETES_VERSION` in Vagrantfile (e.g., "1.35.0")
2. Ensure the version exists in the Kubernetes apt repository
3. Run `vagrant destroy -f && vagrant up`

### Changing Node Resources
1. Edit the `NODES` array in Vagrantfile
2. Modify `cpus` or `memory` values
3. Run `vagrant reload` to apply changes

### Changing Network Configuration
1. Update `POD_NETWORK_CIDR` or node IPs in Vagrantfile
2. Update corresponding IPs in `playbooks/common.yml` (lines 67-69)
3. Full reprovisioning required: `vagrant destroy -f && vagrant up`

### Adding Additional Workers
1. Add new node definition to `NODES` array in Vagrantfile
2. Add corresponding entry in `playbooks/common.yml` /etc/hosts section
3. Run `vagrant up <new-node-name>`

## Troubleshooting

### Join Command Issues
If workers fail to join:
1. Check `playbooks/k8s-join-command.sh` exists and contains valid token
2. Token expires after 24 hours - regenerate on control-plane:
   ```bash
   vagrant ssh k8s-control-plane
   kubeadm token create --print-join-command
   ```
3. Update `playbooks/k8s-join-command.sh` with new command
4. Reprovision workers: `vagrant provision k8s-worker-1 --provision-with ansible`

### Cilium Not Ready
1. Check Cilium pods: `vagrant ssh k8s-control-plane -c "kubectl get pods -n kube-system -l k8s-app=cilium"`
2. Check Cilium status: `vagrant ssh k8s-control-plane -c "cilium status"`
3. View logs: `vagrant ssh k8s-control-plane -c "kubectl logs -n kube-system -l k8s-app=cilium"`

### Node NotReady
1. Verify containerd is running: `vagrant ssh <node> -c "systemctl status containerd"`
2. Check kubelet logs: `vagrant ssh <node> -c "journalctl -u kubelet -f"`
3. Verify CNI is operational on control-plane before expecting workers to be Ready
