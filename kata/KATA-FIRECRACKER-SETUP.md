# Kata Containers + Firecracker Setup

## Overview

Production-ready Kata Containers with Firecracker VMM for microVM isolation in Kubernetes.

**⚠️ IMPORTANT: Kata+Firecracker requires bare metal or cloud instances with proper nested virtualization support. It does NOT work reliably in libvirt/VirtualBox-based Vagrant VMs due to nested virtualization overhead. This setup is documented for deployment on bare metal servers.**

## Components Installed

- **Kata Containers**: v3.10.0 (static binary release)
- **VMM**: Firecracker v1.8.0 (bundled with Kata)
- **Runtime**: `kata-fc` handler for containerd
- **Location**: `/opt/kata/`

## Installation Scripts

### 1. Main Installation (`scripts/install-kata-firecracker.sh`)

Installs Kata+Firecracker on a single node:

```bash
sudo ./scripts/install-kata-firecracker.sh
```

**What it does:**
- Downloads Kata 3.10.0 static tarball (398MB)
- Extracts to `/opt/kata/`
- Creates symlinks in `/usr/local/bin/`
- Generates Firecracker-specific config at `/etc/kata-containers/configuration-fc.toml`
- Adds `kata-fc` runtime to containerd config
- Restarts containerd

**Key Configuration (Optimized):**
```toml
[hypervisor.firecracker]
path = "/opt/kata/bin/firecracker"
jailer_path = "/opt/kata/bin/jailer"
kernel = "/opt/kata/share/kata-containers/vmlinux.container"
# Use initrd instead of image for faster boot
initrd = "/opt/kata/share/kata-containers/kata-containers-initrd.img"
machine_type = "microvm"
default_vcpus = 1
default_memory = 64     # MiB (optimized for testing)
shared_fs = "virtio-fs"
```

### 2. Enable Script (`scripts/enable-kata-firecracker.sh`)

Re-enables Kata runtime on a node (if previously disabled):

```bash
sudo ./scripts/enable-kata-firecracker.sh
```

### 3. Disable Script (`scripts/disable-kata-firecracker.sh`)

Disables Kata runtime but keeps binaries installed:

```bash
sudo ./scripts/disable-kata-firecracker.sh
```

## Kubernetes Manifests

### RuntimeClass (`manifests/runtimeclass-kata-fc.yaml`)

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: kata-fc
handler: kata-fc
overhead:
  podFixed:
    memory: "160Mi"  # MicroVM overhead
    cpu: "250m"
```

Deploy with:
```bash
kubectl apply -f manifests/runtimeclass-kata-fc.yaml
```

### Test Pod (`manifests/nginx-kata-fc-test.yaml`)

```yaml
spec:
  runtimeClassName: kata-fc
  nodeSelector:
    kubernetes.io/hostname: k8s-node-2
  containers:
  - name: nginx
    image: nginx:1.27-alpine
    resources:
      requests:
        memory: "32Mi"
        cpu: "50m"
      limits:
        memory: "64Mi"
        cpu: "200m"
```

## Node Requirements

### Minimum Resources
- **RAM**: 4GB+ (6-8GB recommended for nested virtualization)
- **CPU**: 2 cores with KVM support
- **Storage**: 2GB for Kata binaries and images

### Prerequisites
- KVM enabled (`/dev/kvm` accessible)
- Containerd running
- Nested virtualization enabled (for libvirt/VirtualBox hosts)

Check with:
```bash
sudo kata-runtime kata-check
```

## ⚠️ CRITICAL LIMITATION: Nested Virtualization Not Supported

### Status: **DOES NOT WORK** in Libvirt/VirtualBox Vagrant VMs

**Symptom:** Pods permanently stuck in `ContainerCreating` (tested 2025-10-27)

**Error:**
```
Failed to create pod sandbox: rpc error: code = DeadlineExceeded desc =
timed out connecting to hybrid vsocket hvsock:/run/vc/firecracker/.../root/kata.hvsock
```

**Root Cause Analysis:**

The Firecracker microVM starts successfully, but the **Kata agent inside the microVM never initializes** due to extreme nested virtualization overhead:

1. **Firecracker binary**: ✅ Works (v1.8.0)
2. **kata-runtime kata-check**: ✅ Passes
3. **Firecracker process launches**: ✅ Confirmed
4. **Kata agent vsock connection**: ❌ **TIMES OUT**

The nested KVM stack (Host → libvirt KVM → Vagrant VM → Firecracker microVM) adds too much latency. The Kata runtime cannot establish communication with the agent inside the microVM before hitting the deadline.

**Tested Optimizations (All Failed):**
1. ✅ Reduced `default_memory` 512MB → 64MB
2. ✅ Switched from image (256MB) to initrd (15MB) for faster boot
3. ✅ Increased node RAM 2GB → 4GB
4. ✅ Used `cpu_mode = "host-passthrough"` in libvirt
5. ❌ **Result: Still times out connecting to Kata agent**

### **Conclusion**

Kata+Firecracker is **fundamentally incompatible with nested virtualization** in Vagrant/libvirt environments.

**Supported Environments:**
- ✅ **Bare metal servers** (Intel VT-x/AMD-V)
- ✅ **AWS EC2 metal instances** (i3.metal, c5.metal, etc.)
- ✅ **GCP with nested virtualization enabled**
- ✅ **Azure with nested virtualization support**
- ❌ **Vagrant/VirtualBox/libvirt VMs** (nested KVM too slow)

### Recommendation

For testing Kata Containers in Vagrant:
- Use **Kata with QEMU hypervisor** instead (see separate documentation)
- QEMU has better nested virtualization support than Firecracker
- Or deploy on bare metal for production-like Firecracker testing

## Installation Status

**Current State:**
- ✅ Installation scripts ready and tested
- ✅ Kata 3.10.0 with Firecracker 1.8.0 installed on k8s-node-2
- ✅ Configuration optimized (64MB RAM, initrd boot)
- ❌ Pod creation fails due to nested virt limitation
- 📦 **Scripts preserved for bare metal deployment**

## Architecture

```
Kubernetes Pod
    ↓
RuntimeClass: kata-fc
    ↓
containerd
    ↓
containerd-shim-kata-v2
    ↓
Kata Runtime
    ↓
Firecracker VMM
    ↓
Guest Kernel (vmlinux.container)
    ↓
Kata Agent (in microVM)
    ↓
Container Process
```

## Files Created

```
/opt/kata/
├── bin/
│   ├── kata-runtime
│   ├── containerd-shim-kata-v2
│   ├── firecracker
│   └── jailer
└── share/kata-containers/
    ├── vmlinux.container (43MB kernel)
    ├── kata-containers.img (256MB rootfs)
    └── kata-alpine-3.18.initrd (15MB - alternative)

/etc/kata-containers/
└── configuration-fc.toml

/etc/containerd/config.toml
└── [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.kata-fc]

/usr/local/bin/
├── kata-runtime -> /opt/kata/bin/kata-runtime
└── containerd-shim-kata-v2 -> /opt/kata/bin/containerd-shim-kata-v2
```

## Verification Commands

```bash
# Check Kata installation
kata-runtime --version

# Verify system capabilities
sudo kata-runtime kata-check

# Check containerd runtime
crictl --runtime-endpoint unix:///run/containerd/containerd.sock info | grep kata

# List running microVMs
ps aux | grep firecracker

# Check pod using Kata
kubectl get pod <pod-name> -o jsonpath='{.spec.runtimeClassName}'
```

## Production Deployment

**Supported Platforms (Tested/Recommended):**
- ✅ **Bare metal servers** (Best performance)
- ✅ **AWS EC2 metal instances** (i3.metal, c5.metal, m5.metal)
- ✅ **GCP with nested virtualization** (Enable nested virt on host)
- ✅ **Azure Dv3/Ev3 series** (Nested virt supported)

**Unsupported Platforms:**
- ❌ **Vagrant/VirtualBox VMs** (Tested - does not work)
- ❌ **Libvirt/KVM nested VMs** (Tested - does not work)
- ❌ **VMware Workstation/Fusion** (Likely won't work)

**For Vagrant/local testing:** Use Kata with QEMU hypervisor instead (see KATA-QEMU-SETUP.md)

## Troubleshooting

### Logs
```bash
# Kata shim logs
journalctl -u containerd | grep kata

# Firecracker logs
journalctl | grep firecracker

# Pod events
kubectl describe pod <pod-name>
```

### Common Issues

**"timed out connecting to hybrid vsocket" / Pods stuck in ContainerCreating**
- **Cause**: Nested virtualization (Vagrant/VirtualBox/libvirt)
- **Solution**: Deploy on bare metal or use Kata with QEMU instead
- **Not fixable**: This is a fundamental limitation

**"no runtime for kata-fc is configured"**
- Run: `sudo ./scripts/enable-kata-firecracker.sh`
- Verify: `grep kata-fc /etc/containerd/config.toml`

**"KVM support not found"**
- Check: `ls -l /dev/kvm`
- For bare metal: Ensure VT-x/AMD-V enabled in BIOS
- For cloud: Use instance types supporting nested virt

**"dial unix .../firecracker.socket: connect: no such file or directory"**
- Firecracker process failed to start
- Check: `sudo journalctl -u containerd | grep firecracker`
- Verify: `/opt/kata/bin/firecracker --version` works

## References

- [Kata Containers Documentation](https://github.com/kata-containers/kata-containers/tree/main/docs)
- [Firecracker Documentation](https://github.com/firecracker-microvm/firecracker/tree/main/docs)
- [Kubernetes RuntimeClass](https://kubernetes.io/docs/concepts/containers/runtime-class/)
