# Testing Guide for Vagrant Kubernetes Cluster

## 🧪 Step-by-Step Testing Instructions

Follow this guide to test the complete cluster setup from scratch.

### Phase 1: Test Hypervisor Switching Script

**Current State Check:**
```bash
# Check what's currently loaded
lsmod | grep -E "(kvm|vbox)"

# You should see both KVM and VirtualBox modules loaded
```

**Test 1: Switch to VirtualBox**
```bash
./switch-to-virtualbox.sh
```

**Expected Output:**
- ✅ Unloads VirtualBox modules cleanly
- ✅ Stops KVM services (libvirtd, virtlogd, virtlockd)
- ✅ Unloads KVM modules (kvm_intel, kvm)
- ✅ Restarts vboxdrv service (or loads modules manually)
- ✅ Verifies VirtualBox is functional
- ✅ Checks vboxusers group membership

**Success Criteria:**
- Script completes without errors
- Final output shows only vbox modules loaded: `vboxdrv`, `vboxnetflt`, `vboxnetadp`
- No KVM modules in `lsmod` output
- `VBoxManage list vms` works without errors

**If you see "User not in vboxusers group" warning:**
```bash
# Log out and log back in, then re-run the script
```

---

### Phase 2: Test Vagrant Cluster Bring-Up

**Test 2: Start Control Plane**
```bash
vagrant up k8s-control-plane
```

**Watch for:**
1. ✅ Vagrant box download (first time: ~600-800MB, ~5-10 minutes)
2. ✅ VM creation and boot
3. ✅ Ansible provisioning stages:
   - `common` - System configuration
   - `binaries` - Install Kubernetes binaries
   - `containerd` - Configure container runtime
   - `control-plane` - Initialize Kubernetes
   - `calico` - Install CNI
   - `untaint` - Allow scheduling on control plane

**Expected Duration:** 10-15 minutes

**Success Criteria:**
- No errors in output
- VM is running: `vagrant status` shows "running (virtualbox)"
- Can SSH: `vagrant ssh k8s-control-plane`
- Kubernetes API is up: `vagrant ssh k8s-control-plane -c "kubectl get nodes"`

**If errors occur:**
- Check error message carefully
- Note the exact playbook/task that failed
- Check VirtualBox modules still loaded: `lsmod | grep vbox`
- Share error output for debugging

---

**Test 3: Start Worker Nodes**
```bash
vagrant up k8s-worker-1 k8s-worker-2
```

**Watch for:**
1. ✅ VM creation and boot for both workers
2. ✅ Ansible provisioning:
   - `common` - System configuration
   - `binaries` - Install Kubernetes binaries
   - `containerd` - Configure container runtime
   - `worker` - Join cluster using token

**Expected Duration:** 8-12 minutes

**Success Criteria:**
- Both workers show "running (virtualbox)"
- Workers joined cluster successfully
- All nodes show "Ready"

---

### Phase 3: Cluster Verification

**Test 4: Run Verification Script**
```bash
./verify-cluster.sh
```

**Expected Output:**
```
NAME                 STATUS   ROLES           AGE   VERSION
k8s-control-plane    Ready    control-plane   Xm    v1.34.1
k8s-worker-1         Ready    <none>          Xm    v1.34.1
k8s-worker-2         Ready    <none>          Xm    v1.34.1

All system pods running in kube-system namespace
Calico pods running successfully
```

**Manual Checks:**
```bash
# Check nodes
vagrant ssh k8s-control-plane -c "kubectl get nodes -o wide"

# Check all pods
vagrant ssh k8s-control-plane -c "kubectl get pods -A"

# Check Calico specifically
vagrant ssh k8s-control-plane -c "kubectl get pods -n kube-system -l k8s-app=calico-node"

# Deploy test workload
vagrant ssh k8s-control-plane -c "kubectl create deployment nginx --image=nginx"
vagrant ssh k8s-control-plane -c "kubectl get pods"
```

**Success Criteria:**
- All nodes show STATUS: Ready
- All system pods are Running
- Test nginx pod starts successfully

---

### Phase 4: Test Hypervisor Switch Back to KVM

**Test 5: Stop Cluster and Switch to KVM**
```bash
# Stop all VMs first
vagrant halt

# Verify all VMs stopped
vagrant status

# Switch to KVM
./switch-to-kvm.sh
```

**Expected Output:**
- ✅ Detects no running VirtualBox VMs
- ✅ Unloads VirtualBox modules
- ✅ Loads KVM modules (kvm_intel/kvm_amd, kvm)
- ✅ Starts libvirt services
- ✅ Verifies KVM is functional

**Success Criteria:**
- Script completes without errors
- Only KVM modules loaded: `lsmod | grep kvm`
- No VirtualBox modules: `lsmod | grep vbox` returns nothing
- If virsh installed: `virsh list --all` works

---

**Test 6: Switch Back to VirtualBox and Resume Cluster**
```bash
# Switch back
./switch-to-virtualbox.sh

# Resume cluster
vagrant up

# Quick check
vagrant ssh k8s-control-plane -c "kubectl get nodes"
```

**Success Criteria:**
- Switch completes cleanly
- Cluster resumes without reprovisioning
- All nodes still Ready
- Previous nginx deployment still exists

---

## 🐛 Error Documentation Template

If you encounter errors, please document them like this:

```
PHASE: [1/2/3/4/5/6]
TEST: [Test number and name]
COMMAND: [Exact command that failed]
ERROR OUTPUT:
[Paste complete error message]

SYSTEM STATE:
- lsmod output: [paste lsmod | grep -E "(kvm|vbox)"]
- vagrant status: [paste output]
- VirtualBox version: [paste VBoxManage --version]

ADDITIONAL CONTEXT:
[Any other relevant information]
```

---

## ✅ Quick Success Checklist

Use this to track your testing progress:

- [ ] Test 1: switch-to-virtualbox.sh completes successfully
- [ ] Test 2: Control plane starts and Kubernetes initializes
- [ ] Test 3: Both workers start and join cluster
- [ ] Test 4: Cluster verification passes (all nodes Ready)
- [ ] Test 5: Can switch back to KVM successfully
- [ ] Test 6: Can switch back to VirtualBox and resume cluster

---

## 📊 Performance Benchmarks

Expected timings on a typical system:

| Operation | Time |
|-----------|------|
| Vagrant box download | 5-10 min (first time only) |
| Control plane provision | 8-12 min |
| Worker provision (both) | 8-12 min |
| **Total first start** | **20-30 min** |
| Subsequent starts | 2-5 min |
| Hypervisor switch | 5-15 seconds |

---

## 🚀 Ready to Test?

Start with **Test 1** and work through each phase. Document any issues you encounter!

**Good luck! 🎉**
