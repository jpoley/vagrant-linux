# Kubernetes Cluster Fixes Applied

## Date: October 23, 2025

## Environment
- **Host**: Mac M2 (ARM64) running macOS 26.0.1
- **Hypervisor**: VirtualBox 7.1.4
- **Box**: hashicorp-education/ubuntu-24-04 (0.1.0) - ARM64 compatible ✅
- **Target**: 3-node Kubernetes cluster (1 control-plane + 2 workers)

## Issues Discovered & Resolved

### ❌ Issue #1: Invalid Kubernetes Version
**Problem**: Vagrantfile specified Kubernetes version `1.34.1` which doesn't exist
- Kubernetes 1.34 hasn't been released yet (as of January 2025)
- Latest stable version is 1.32.x
- This caused the kubernetes.yml playbook to fail when trying to install non-existent packages

**Fix Applied**:
```ruby
# Vagrantfile line 10
- KUBERNETES_VERSION = "1.34.1"
+ KUBERNETES_VERSION = "1.32.0"
```

**Files Modified**: `Vagrantfile`

---

### ❌ Issue #2: Incorrect GPG Key Format for New Kubernetes Repository
**Problem**: The playbooks/kubernetes.yml was not properly handling the GPG key for the new pkgs.k8s.io repository structure
- The new Kubernetes package repository requires GPG keys in dearmored (.gpg) format
- The playbook was trying to use the key directly without converting it

**Fix Applied**:
```yaml
# playbooks/kubernetes.yml lines 15-29
- name: Download Kubernetes GPG key
  get_url:
    url: "https://pkgs.k8s.io/core:/stable:/v{{ k8s_version_short }}/deb/Release.key"
    dest: /tmp/kubernetes-release.key
    mode: '0644'

- name: Dearmor Kubernetes GPG key
  shell: gpg --dearmor < /tmp/kubernetes-release.key > /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  args:
    creates: /etc/apt/keyrings/kubernetes-apt-keyring.gpg

- name: Set GPG key permissions
  file:
    path: /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    mode: '0644'

- name: Add Kubernetes repository
  apt_repository:
    repo: "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v{{ k8s_version_short }}/deb/ /"
    state: present
    filename: kubernetes
```

**Files Modified**: `playbooks/kubernetes.yml`

---

### ⚠️ Issue #3: VirtualBox Guru Meditation Error (VM Crash)
**Problem**: VM crashed during Cilium CNI installation with VirtualBox "guru meditation" error
- Control-plane node had only 4GB RAM
- Cilium installation is memory-intensive (downloading images, starting pods)
- VirtualBox on ARM64 may be more sensitive to resource constraints

**Fix Applied**:
```ruby
# Vagrantfile line 16
NODES = [
-  { name: "k8s-control-plane", ip: "192.168.57.10", cpus: 2, memory: 4096, role: "control-plane" },
+  { name: "k8s-control-plane", ip: "192.168.57.10", cpus: 2, memory: 6144, role: "control-plane" },
   { name: "k8s-worker-1", ip: "192.168.57.11", cpus: 2, memory: 2048, role: "worker" },
   { name: "k8s-worker-2", ip: "192.168.57.12", cpus: 2, memory: 2048, role: "worker" }
]
```

**Rationale**: Increased control-plane RAM from 4GB to 6GB (4096MB → 6144MB)

**Files Modified**: `Vagrantfile`

---

## Verification Status

### ✅ Confirmed Working
1. VirtualBox 7.1.4 runs on Apple Silicon M2 Mac
2. hashicorp-education/ubuntu-24-04 box has ARM64 support
3. VM boot and SSH connectivity work correctly
4. Ansible playbooks execute successfully:
   - ✅ common.yml (system prep, kernel modules, networking)
   - ✅ containerd.yml (container runtime installation)
   - ✅ kubernetes.yml (kubelet, kubeadm, kubectl 1.32.0)
   - ✅ control-plane.yml (kubeadm init, kubeconfig setup)

### 🔄 In Progress
5. Cilium CNI installation and verification
6. Worker node joining
7. Full cluster validation

---

## Provisioning Flow

The Vagrantfile provisions nodes in this exact sequence:

1. **common.yml** - All nodes
   - Disable swap
   - Load kernel modules (overlay, br_netfilter)
   - Configure sysctl for Kubernetes networking
   - Add cluster nodes to /etc/hosts

2. **containerd.yml** - All nodes
   - Install containerd from Docker repository
   - Configure systemd cgroup driver
   - Enable CRI plugin

3. **kubernetes.yml** - All nodes
   - Add Kubernetes 1.32 apt repository with proper GPG key
   - Install kubelet, kubeadm, kubectl
   - Hold packages to prevent auto-updates

4. **control-plane.yml** - Control-plane only
   - Run `kubeadm init` with `--skip-phases=addon/kube-proxy` (Cilium replaces kube-proxy)
   - Set up kubeconfig for vagrant and root users
   - Generate and save join command to `playbooks/k8s-join-command.sh`

5. **cilium.yml** - Control-plane only
   - Download Cilium CLI
   - Install Cilium 1.18.0 with `kubeProxyReplacement=true`
   - Wait for Cilium to become ready (5 min timeout)

6. **untaint.yml** - Control-plane only
   - Remove NoSchedule taint to allow pod scheduling on control-plane

7. **workers.yml** - Worker nodes only
   - Copy join command from playbooks directory
   - Join worker to cluster using kubeadm

---

## Key Design Decisions

1. **No kube-proxy**: Cilium handles all kube-proxy functionality (`--skip-phases=addon/kube-proxy`)
2. **Control-plane scheduling**: Control-plane is untainted for dev/test workloads
3. **Version pinning**: Kubernetes packages are held to prevent unexpected upgrades
4. **ARM64 native**: All components run natively on ARM64 architecture

---

## Next Steps

1. Complete current provisioning run with increased RAM
2. Verify Cilium CNI is functioning correctly
3. Provision and test worker node joining
4. Run comprehensive cluster validation tests
5. Create validation script for future testing
6. Git commit all working changes with tag `v1.0-working`
7. Document in journal.md

---

## Files Modified Summary

| File | Change | Reason |
|------|--------|--------|
| `Vagrantfile` | K8s version: 1.34.1 → 1.32.0 | Use valid/existing K8s version |
| `Vagrantfile` | Control-plane RAM: 4096 → 6144 | Prevent VM crashes during Cilium install |
| `playbooks/kubernetes.yml` | Update GPG key handling | Support new pkgs.k8s.io repository format |

---

## Testing Methodology

1. Destroy all VMs: `vagrant destroy -f`
2. Start fresh: `vagrant up k8s-control-plane`
3. Monitor logs: `/tmp/vagrant-cp-YYYYMMDD-HHMMSS.log`
4. Verify each stage completes successfully
5. Check cluster status: `vagrant ssh k8s-control-plane -c "kubectl get nodes"`
