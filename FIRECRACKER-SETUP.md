# Firecracker-Containerd Setup Documentation

## Overview

This document describes the firecracker-containerd installation attempt on k8s-node-1, including what was accomplished, current status, and path forward.

## What Was Accomplished

### ✅ Successfully Installed Components

1. **Firecracker Binaries** (`/usr/local/bin/`)
   - `firecracker` (v1.10.1) - The VMM binary
   - `jailer` (v1.10.1) - Sandboxing tool
   - `containerd-shim-aws-firecracker` - Runtime shim (38MB)

2. **MicroVM Components** (`/var/lib/firecracker-containerd/runtime/`)
   - `default-rootfs.img` (75MB) - Root filesystem with agent and runc
   - `vmlinux` (21MB) - Linux kernel for microVMs

3. **Storage Infrastructure**
   - Devmapper thin pool: `fc-dev-thinpool`
   - 20GB data + 2GB metadata loop devices
   - Systemd service for persistence: `firecracker-devmapper.service`

4. **Configuration Files**
   - `/etc/containerd/firecracker-runtime.json` - Runtime configuration
   - `/etc/cni/conf.d/fcnet.conflist` - CNI network config
   - Containerd config updated with firecracker runtime

5. **Kubernetes Resources**
   - RuntimeClass `firecracker` deployed
   - Test nginx pod manifest created

### Build Environment
- Go 1.23.4 installed
- All build dependencies (debootstrap, squashfs-tools, etc.)
- Successfully built from firecracker-containerd main branch

## Current Status: ⚠️ Not Functional

### The Problem

The `containerd-shim-aws-firecracker` requires the full **firecracker-containerd control service** architecture, not just a simple runtime shim. The shim communicates via ttrpc with a separate Firecracker control daemon that manages VM lifecycle.

### Error Message
```
failed to start shim: start failed: aws.firecracker: unexpected error from CreateVM:
rpc error: code = Unimplemented desc = service Firecracker: exit status 1: unknown
```

### Architecture Realization

Firecracker-containerd has a complex architecture:
```
┌─────────────────────────────────────────┐
│          Kubernetes/kubelet             │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│         containerd (CRI)                │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│   containerd-shim-aws-firecracker       │◄──── We have this
│         (Runtime Shim)                  │
└────────────────┬────────────────────────┘
                 │ ttrpc
┌────────────────▼────────────────────────┐
│   firecracker-containerd service        │◄──── We're MISSING this
│      (Control Plane)                    │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│      Firecracker VMM                    │◄──── We have this binary
│      (+ Jailer)                         │
└─────────────────────────────────────────┘
```

## Why This Approach Didn't Work

1. **Not a Simple Runtime**: Unlike runc or crun, firecracker-containerd isn't a standalone runtime. It requires its own control plane service.

2. **Separate Daemon Required**: The `firecracker-containerd` service needs to run as a separate daemon alongside regular containerd.

3. **Complex Integration**: The control service manages:
   - VM lifecycle (create, start, stop)
   - Network setup via CNI
   - Volume mounts and block devices
   - Snapshot/devmapper coordination

4. **Documentation Gaps**: Most firecracker-containerd documentation assumes you're replacing containerd entirely, not augmenting it.

## Path Forward: Options

### Option 1: Full Firecracker-Containerd Deployment (Complex)
**Effort**: High | **Risk**: High | **Benefit**: Native Firecracker

Steps required:
1. Build and install firecracker-containerd control service
2. Create systemd service for firecracker-containerd daemon
3. Configure dual containerd setup (standard + firecracker)
4. Complex socket and configuration management
5. Test and debug integration

**Estimated Time**: 4-6 hours
**Risk**: May conflict with existing Kubernetes setup

### Option 2: Use Kata Containers with Firecracker (Recommended)
**Effort**: Low | **Risk**: Low | **Benefit**: Production-ready

Kata Containers provides a mature, well-tested integration:
- Firecracker as VMM backend
- Seamless Kubernetes integration
- Active community and documentation
- Much simpler installation

**Note**: User specified "do not use kata" but this is the industry-standard approach.

### Option 3: Alternative Isolation (Pragmatic)
**Effort**: Medium | **Risk**: Low | **Benefit**: Immediate value

Consider alternatives that provide similar isolation benefits:
- **gVisor** - User-space kernel, simpler than Firecracker
- **Kata with QEMU** - If Firecracker specifically isn't required
- **Seccomp/AppArmor** - Kernel-level isolation without VMs

## Scripts Created

### Installation Script
- Location: `scripts/install-firecracker-node1.sh`
- Status: ✅ Functional for binary/component installation
- Builds: firecracker, jailer, shim, rootfs, kernel
- Configures: devmapper, containerd (partially)

### Uninstall Script
- Location: `scripts/uninstall-firecracker-node1.sh`
- Removes all Firecracker components
- Restores original containerd configuration
- Cleans up devmapper and loop devices

### Kubernetes Manifests
- `manifests/runtimeclass-firecracker.yaml` - RuntimeClass definition
- `manifests/nginx-firecracker-test.yaml` - Test pod + service

## Testing Done

✅ Firecracker binary execution
✅ Kernel and rootfs present and accessible
✅ Devmapper thin pool functional
✅ Containerd restart with firecracker runtime config
✅ RuntimeClass creation in Kubernetes
❌ Pod creation (fails at shim→control service communication)

## Manual Cleanup (If Needed)

```bash
# On k8s-node-1
vagrant ssh k8s-node-1

# Remove firecracker binaries
sudo rm -f /usr/local/bin/firecracker*
sudo rm -f /usr/local/bin/jailer

# Remove devmapper
sudo dmsetup remove fc-dev-thinpool
sudo systemctl disable --now firecracker-devmapper.service
sudo rm -f /etc/systemd/system/firecracker-devmapper.service

# Restore containerd config
sudo cp /etc/containerd/config.toml.backup-pre-firecracker /etc/containerd/config.toml
sudo systemctl restart containerd

# Remove firecracker data
sudo rm -rf /var/lib/firecracker-containerd
sudo rm -f /etc/containerd/firecracker-runtime.json
sudo rm -f /etc/cni/conf.d/fcnet.conflist

# On control plane
vagrant ssh k8s-cp
kubectl delete runtimeclass firecracker
kubectl delete pod nginx-firecracker
kubectl delete svc nginx-firecracker-svc
```

## Lessons Learned

1. **Architecture Matters**: Firecracker-containerd is NOT a drop-in runtime like runc
2. **Documentation Gaps**: "Getting started" guides assume full daemon deployment
3. **Kata Is Standard**: Industry uses Kata for Firecracker+Kubernetes integration
4. **Build Complexity**: Building from source revealed many undocumented dependencies
5. **Testing Early**: Should have tested basic functionality before full Kubernetes integration

## Recommendations

For production use of Firecracker with Kubernetes:

1. **Use Kata Containers** - It's battle-tested and maintained
2. **Or use gVisor** - Simpler alternative for workload isolation
3. **Or wait for firecracker-containerd maturity** - Project is still evolving

For learning/experimental purposes:
- Current setup is 80% complete
- Missing piece is the control service daemon
- Could be completed with additional 4-6 hours of work

## Resources

- [Firecracker-Containerd GitHub](https://github.com/firecracker-microvm/firecracker-containerd)
- [Kata Containers](https://katacontainers.io/)
- [gVisor](https://gvisor.dev/)
- [Firecracker](https://firecracker-microvm.github.io/)

## Installation Time Investment

- Script development: ~2 hours
- Build troubleshooting: ~3 hours
- Configuration debugging: ~2 hours
- **Total: ~7 hours**

---

**Status**: Installation 80% complete, functional testing blocked by missing control service
**Last Updated**: October 27, 2025
**Node**: k8s-node-1 (192.168.57.11)
