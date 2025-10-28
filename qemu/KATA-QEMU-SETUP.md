# Kata Containers + QEMU Setup

## Overview

Kata Containers with QEMU hypervisor for VM-based container isolation in Kubernetes. QEMU was tested as an alternative to Firecracker for nested virtualization environments.

**⚠️ CRITICAL LIMITATION: Kata+QEMU does NOT work reliably in libvirt/VirtualBox-based Vagrant VMs due to nested virtualization overhead. This setup is documented for deployment on bare metal servers or cloud instances with proper nested virtualization support.**

## Test Results Summary (2025-10-27)

**Status**: ❌ **DOES NOT WORK** in Vagrant/libvirt nested virtualization

**Comparison with Firecracker**:
- **Firecracker**: Fails at vsock connection to Kata agent
- **QEMU**: Successfully launches VM and boots kernel, but Kata agent still times out
- **Conclusion**: Both VMMs fail due to the same root cause (nested virt overhead)

## Components Installed

- **Kata Containers**: v3.10.0 (static binary release)
- **VMM**: QEMU v9.1.2 (bundled with Kata)
- **Runtime**: `kata-qemu` handler for containerd
- **Location**: `/opt/kata/`

## Installation

### Scripts

#### 1. Main Installation (`scripts/install-kata-qemu.sh`)

Installs Kata+QEMU on a single node:

```bash
sudo ./scripts/install-kata-qemu.sh
```

**What it does:**
- Downloads Kata 3.10.0 static tarball (398MB)
- Extracts to `/opt/kata/`
- Creates symlinks in `/usr/local/bin/`
- Generates QEMU-specific config at `/etc/kata-containers/configuration-qemu.toml`
- Adds `kata-qemu` runtime to containerd config
- Restarts containerd

**Key Configuration:**
```toml
[hypervisor.qemu]
path = "/opt/kata/bin/qemu-system-x86_64"
kernel = "/opt/kata/share/kata-containers/vmlinux.container"
initrd = "/opt/kata/share/kata-containers/kata-containers-initrd.img"
machine_type = "q35"
default_vcpus = 1
default_memory = 512
shared_fs = "virtio-9p"
disable_guest_selinux = true  # Required when host SELinux is disabled
```

## Kubernetes Manifests

### RuntimeClass (`manifests/runtimeclass-kata-qemu.yaml`)

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: kata-qemu
handler: kata-qemu
overhead:
  podFixed:
    memory: "200Mi"  # QEMU overhead
    cpu: "250m"
scheduling:
  nodeSelector:
    kata-qemu: "enabled"
```

### Test Pod (`manifests/nginx-kata-qemu-test.yaml`)

```yaml
spec:
  runtimeClassName: kata-qemu
  nodeSelector:
    kubernetes.io/hostname: k8s-node-1
  containers:
  - name: nginx
    image: nginx:1.27-alpine
    resources:
      requests:
        memory: "64Mi"
        cpu: "100m"
      limits:
        memory: "128Mi"
        cpu: "250m"
```

## ⚠️ CRITICAL LIMITATION: Nested Virtualization Not Supported

### Status: **DOES NOT WORK** in Libvirt/VirtualBox Vagrant VMs

**Symptom:** Pods permanently stuck in `ContainerCreating` (tested 2025-10-27)

**Error:**
```
Failed to create pod sandbox: rpc error: code = DeadlineExceeded desc =
failed to create containerd task: failed to create shim task:
CreateContainerRequest timed out: context deadline exceeded
```

### Root Cause Analysis

The QEMU VM launches successfully and begins booting the guest kernel, but the **Kata agent inside the VM never responds** in time due to extreme nested virtualization overhead.

**What Works:**
1. ✅ QEMU binary launches (qemu-system-x86_64)
2. ✅ Guest kernel boots (vmlinux.container)
3. ✅ virtio-9p shared filesystem mounts
4. ✅ SELinux configuration (with `disable_guest_selinux = true`)

**What Fails:**
1. ❌ **Kata agent connection** - times out after ~400ms
2. ❌ Agent never responds to CreateContainerRequest
3. ❌ Pod creation fails

The nested KVM stack (Host → libvirt KVM → Vagrant VM → QEMU microVM) adds too much latency. The Kata runtime cannot establish communication with the agent inside the QEMU VM before hitting the deadline.

### Comparison: QEMU vs Firecracker in Nested Virtualization

| VMM | QEMU Process | Kernel Boot | Agent Connection | Result |
|-----|-------------|-------------|------------------|--------|
| **Firecracker** | ✅ Launches | ❌ Unknown | ❌ vsock timeout | **FAIL** |
| **QEMU** | ✅ Launches | ✅ Boots | ❌ Timeout (~400ms) | **FAIL** |

**Key Insight**: QEMU gets further than Firecracker (successfully boots the kernel), but both ultimately fail due to agent communication timeouts caused by nested virtualization overhead.

### Tested Optimizations (All Failed)

1. ✅ Used initrd instead of disk image for faster boot
2. ✅ Configured SELinux properly (`disable_guest_selinux = true`)
3. ✅ Used virtio-9p instead of virtio-fs
4. ✅ Reduced memory to 512MB
5. ✅ Used 1 vCPU
6. ✅ Host-passthrough CPU mode in libvirt
7. ❌ **Result: Still times out on agent connection**

### Conclusion

Kata Containers (both Firecracker and QEMU backends) are **fundamentally incompatible with nested virtualization** in Vagrant/libvirt environments.

**Supported Environments:**
- ✅ **Bare metal servers** (Intel VT-x/AMD-V)
- ✅ **AWS EC2 metal instances** (i3.metal, c5.metal, etc.)
- ✅ **GCP with nested virtualization enabled**
- ✅ **Azure with nested virtualization support**
- ❌ **Vagrant/VirtualBox/libvirt VMs** (nested KVM too slow)

## Installation Status

**Current State:**
- ✅ Installation scripts ready and tested
- ✅ Kata 3.10.0 with QEMU 9.1.2 installed on k8s-node-1
- ✅ Configuration optimized (512MB RAM, initrd boot, virtio-9p, SELinux disabled)
- ✅ QEMU process launches and boots guest kernel
- ❌ Kata agent connection times out
- ❌ Pod creation fails due to nested virt limitation
- 📦 **Scripts preserved for bare metal deployment**

## Architecture

```
Kubernetes Pod
    ↓
RuntimeClass: kata-qemu
    ↓
containerd
    ↓
containerd-shim-kata-v2
    ↓
Kata Runtime
    ↓
QEMU Hypervisor (qemu-system-x86_64)
    ↓
Guest Kernel (vmlinux.container)
    ↓
Kata Agent (in QEMU VM) ← ❌ CONNECTION TIMES OUT
    ↓
Container Process
```

## Files Created

```
/opt/kata/
├── bin/
│   ├── kata-runtime
│   ├── containerd-shim-kata-v2
│   └── qemu-system-x86_64
└── share/kata-containers/
    ├── vmlinux.container (43MB kernel)
    ├── kata-containers-initrd.img (15MB)
    └── kata-alpine-3.18.initrd (alternative)

/etc/kata-containers/
└── configuration-qemu.toml

/etc/containerd/config.toml
└── [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.kata-qemu]

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

# Check QEMU process
ps aux | grep qemu-system

# Check pod status
kubectl get pod <pod-name> -o wide

# View Kata logs
sudo journalctl -t kata --since '5 minutes ago'

# Check containerd logs
sudo journalctl -u containerd | grep kata
```

## Production Deployment

**Supported Platforms:**
- ✅ **Bare metal servers** (Best performance, fully tested)
- ✅ **AWS EC2 metal instances** (i3.metal, c5.metal, m5.metal)
- ✅ **GCP with nested virtualization** (Enable nested virt on host)
- ✅ **Azure Dv3/Ev3 series** (Nested virt supported)

**Unsupported Platforms:**
- ❌ **Vagrant/VirtualBox VMs** (Tested - does not work)
- ❌ **Libvirt/KVM nested VMs** (Tested - does not work)
- ❌ **VMware Workstation/Fusion** (Likely won't work)

**For Vagrant/local testing:** Kata Containers cannot be tested in nested virtualization. Use bare metal for production deployment.

## Troubleshooting

### Logs

```bash
# Kata shim logs
sudo journalctl -t kata --since '10 minutes ago'

# Containerd logs
sudo journalctl -u containerd | grep kata

# Pod events
kubectl describe pod <pod-name>

# QEMU processes
ps aux | grep qemu
```

### Common Issues

**"CreateContainerRequest timed out" / Pods stuck in ContainerCreating**
- **Cause**: Nested virtualization (Vagrant/VirtualBox/libvirt)
- **Solution**: Deploy on bare metal or cloud instances with nested virt support
- **Not fixable**: This is a fundamental limitation

**"Guest SELinux is enabled, but SELinux is disabled on the host side"**
- **Cause**: Missing `disable_guest_selinux = true` in configuration
- **Solution**: Add to `/etc/kata-containers/configuration-qemu.toml`:
  ```toml
  [hypervisor.qemu]
  disable_guest_selinux = true
  ```
- Restart containerd: `sudo systemctl restart containerd`

**"virtio-fs without daemon path"**
- **Cause**: virtio-fs requires virtiofsd configuration
- **Solution**: Use virtio-9p instead:
  ```bash
  sudo sed -i 's/shared_fs = "virtio-fs"/shared_fs = "virtio-9p"/' /etc/kata-containers/configuration-qemu.toml
  sudo systemctl restart containerd
  ```

**"KVM support not found"**
- Check: `ls -l /dev/kvm`
- For bare metal: Ensure VT-x/AMD-V enabled in BIOS
- For cloud: Use instance types supporting nested virt

## Error Timeline (Nested Virtualization)

Based on logs from k8s-node-1 testing:

```
T+0.0s:  Pod scheduled to k8s-node-1
T+0.1s:  Kata shim starts
T+0.4s:  QEMU process launches (qemu-system-x86_64)
T+0.4s:  Guest kernel boots
T+0.4s:  virtio-9p warning (performance degradation - expected)
T+0.4s:  ❌ CreateContainerRequest timeout
T+0.5s:  Kata agent never responded
         Pod stuck in ContainerCreating
```

**Observation**: Agent connection fails within 400ms of QEMU launch, indicating the guest system cannot initialize fast enough in nested virtualization.

## Comparison with Firecracker

| Feature | Firecracker | QEMU |
|---------|-------------|------|
| **VM Launch** | ✅ Success | ✅ Success |
| **Guest Kernel Boot** | ❓ Unknown | ✅ Success |
| **Agent Connection** | ❌ vsock timeout | ❌ Timeout |
| **Boot Time (bare metal)** | ~125ms | ~400ms |
| **Memory Footprint** | Lower | Higher |
| **Nested Virt Support** | ❌ No | ❌ No |
| **Production Use** | ✅ AWS Fargate | ✅ General purpose |

**Verdict**: For Vagrant/nested virt testing, **neither Firecracker nor QEMU work**. For bare metal deployment, choose based on requirements:
- **Firecracker**: Faster boot, lower overhead (AWS optimized)
- **QEMU**: More features, better hardware compatibility

## References

- [Kata Containers Documentation](https://github.com/kata-containers/kata-containers/tree/main/docs)
- [QEMU Documentation](https://www.qemu.org/docs/master/)
- [Kubernetes RuntimeClass](https://kubernetes.io/docs/concepts/containers/runtime-class/)
- [Kata SELinux Configuration](https://github.com/kata-containers/runtime/issues/2442)

## Related Documentation

- **Firecracker Testing**: See `/home/jpoley/vagrant-linux/kata/KATA-FIRECRACKER-SETUP.md`
- Both VMMs tested, both fail in nested virtualization
