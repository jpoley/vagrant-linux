#!/bin/bash

################################################################################
# Kata Containers + QEMU Installation Script
#
# This script installs Kata Containers with QEMU as the VMM backend
# on a Kubernetes worker node. QEMU has better nested virtualization
# support than Firecracker, making it suitable for Vagrant/libvirt testing.
#
# Architecture:
#   - Keeps existing containerd for standard workloads
#   - Adds Kata runtime with QEMU VMM
#   - RuntimeClass selector for pod scheduling
#
# Requirements:
#   - Ubuntu 24.04
#   - KVM support (/dev/kvm accessible)
#   - Existing containerd installation
#   - Nested virtualization enabled (libvirt host-passthrough)
#
# Usage:
#   sudo ./install-kata-qemu.sh
#
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
KATA_VERSION="3.10.0"
KATA_TARBALL="kata-static-${KATA_VERSION}-amd64.tar.xz"
KATA_URL="https://github.com/kata-containers/kata-containers/releases/download/${KATA_VERSION}/${KATA_TARBALL}"
INSTALL_DIR="/opt/kata"
BIN_DIR="/usr/local/bin"

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
error_exit() { log_error "$1"; exit 1; }

# Check root
[[ $EUID -ne 0 ]] && error_exit "This script must be run as root (use sudo)"

log_info "========================================"
log_info "Kata Containers + QEMU Setup"
log_info "========================================"
echo ""

################################################################################
# Phase 1: Prerequisites
################################################################################

log_info "Phase 1: Validating prerequisites..."

# Check KVM
[[ ! -e /dev/kvm ]] && error_exit "/dev/kvm not found. KVM support required."
[[ ! -r /dev/kvm ]] || [[ ! -w /dev/kvm ]] && error_exit "/dev/kvm not accessible."
log_success "KVM support verified"

# Check containerd
systemctl is-active --quiet containerd || error_exit "containerd not running"
log_success "containerd is running"

# Check disk space
AVAILABLE_GB=$(df /opt --output=avail --block-size=1G | tail -1 | tr -d ' ')
[[ $AVAILABLE_GB -lt 5 ]] && log_warn "Low disk space: ${AVAILABLE_GB}GB. Need ~2GB for Kata."
log_success "Disk space check passed"

log_success "Phase 1 complete"
echo ""

################################################################################
# Phase 2: Install Kata Containers
################################################################################

log_info "Phase 2: Installing Kata Containers ${KATA_VERSION}..."

# Download Kata
log_info "Downloading Kata static tarball..."
cd /tmp
wget -q --show-progress "$KATA_URL" || error_exit "Failed to download Kata"
log_success "Downloaded Kata tarball"

# Extract to / (tarball contains /opt/kata internally)
log_info "Extracting Kata to ${INSTALL_DIR}..."
tar -xf "$KATA_TARBALL" -C / || error_exit "Failed to extract Kata"
rm -f "$KATA_TARBALL"
log_success "Kata extracted"

# Create symlinks
log_info "Creating symlinks in ${BIN_DIR}..."
ln -sf "${INSTALL_DIR}/bin/kata-runtime" "${BIN_DIR}/kata-runtime"
ln -sf "${INSTALL_DIR}/bin/kata-collect-data.sh" "${BIN_DIR}/kata-collect-data.sh"
ln -sf "${INSTALL_DIR}/bin/containerd-shim-kata-v2" "${BIN_DIR}/containerd-shim-kata-v2"
log_success "Symlinks created"

# Verify installation
if ! kata-runtime --version &>/dev/null; then
    error_exit "Kata installation failed verification"
fi
INSTALLED_VERSION=$(kata-runtime --version | head -1)
log_success "Kata installed: $INSTALLED_VERSION"

log_success "Phase 2 complete"
echo ""

################################################################################
# Phase 3: Configure Kata with QEMU
################################################################################

log_info "Phase 3: Configuring Kata to use QEMU VMM..."

# Backup original config
KATA_CONFIG="${INSTALL_DIR}/share/defaults/kata-containers/configuration.toml"
if [[ -f "$KATA_CONFIG" ]]; then
    cp "$KATA_CONFIG" "${KATA_CONFIG}.backup"
    log_info "Backed up Kata config"
fi

# Create custom Kata configuration for QEMU
log_info "Creating Kata+QEMU configuration..."
mkdir -p /etc/kata-containers
cat > /etc/kata-containers/configuration-qemu.toml <<'EOF'
[hypervisor.qemu]
path = "/opt/kata/bin/qemu-system-x86_64"
kernel = "/opt/kata/share/kata-containers/vmlinux.container"
# Use initrd for faster boot
initrd = "/opt/kata/share/kata-containers/kata-containers-initrd.img"

# Disable guest SELinux (required when host SELinux is disabled)
disable_guest_selinux = true

# QEMU machine type
machine_type = "q35"

# CPU configuration
# Default number of vCPUs
default_vcpus = 1
# Maximum number of vCPUs
default_maxvcpus = 2

# Memory configuration (MiB)
default_memory = 512

# Memory slots
memory_slots = 10

# Shared filesystem (virtio-9p - simpler than virtio-fs, no daemon required)
shared_fs = "virtio-9p"

# Enable virtio-mem for memory hotplug
virtio_mem = false

# Enable IOMMU
enable_iommu = false

# Enable guest swap
enable_guest_swap = false

# Block device configuration
disable_block_device_use = false
block_device_cache_set = true
block_device_cache_direct = false
block_device_cache_noflush = false

# Enable IO threads
enable_iothreads = false

# Entropy source
entropy_source = "/dev/urandom"

# Enable debug (set to true for troubleshooting)
enable_debug = false

[agent.kata]
# Enable debug
enable_debug = false

# Enable tracing
enable_tracing = false

# Kernel modules to load
kernel_modules = []

[runtime]
# Enable debug
enable_debug = false

# Enable tracing
enable_tracing = false

# Internetworking model
internetworking_model = "tcfilter"

# Disable new netns handling
disable_new_netns = false

# Sandbox cgroup only
sandbox_cgroup_only = false

# vCPUs to be hotplugged
hotplug_virt_on_root_bus = false

# Experimental features
experimental = []
EOF

log_success "Kata+QEMU configuration created"

# Check QEMU binary exists
if [[ ! -f "${INSTALL_DIR}/bin/qemu-system-x86_64" ]]; then
    log_warn "QEMU binary not found in Kata package"
    error_exit "QEMU not included in Kata static tarball. This is unexpected."
fi

log_success "Phase 3 complete"
echo ""

################################################################################
# Phase 4: Configure Containerd
################################################################################

log_info "Phase 4: Configuring containerd for Kata+QEMU..."

CONTAINERD_CONFIG="/etc/containerd/config.toml"

# Backup containerd config
if [[ ! -f "${CONTAINERD_CONFIG}.backup-pre-kata-qemu" ]]; then
    cp "$CONTAINERD_CONFIG" "${CONTAINERD_CONFIG}.backup-pre-kata-qemu"
    log_info "Backed up containerd config"
fi

# Check if kata-qemu runtime already exists
if grep -q 'runtimes.kata-qemu' "$CONTAINERD_CONFIG"; then
    log_warn "kata-qemu runtime already exists in containerd config"
else
    log_info "Adding kata-qemu runtime to containerd..."

    # Add kata-qemu runtime configuration
    cat >> "$CONTAINERD_CONFIG" <<'EOF'

# Kata Containers with QEMU VMM
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.kata-qemu]
  runtime_type = "io.containerd.kata.v2"
  privileged_without_host_devices = true
  pod_annotations = ["io.katacontainers.*"]
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.kata-qemu.options]
    ConfigPath = "/etc/kata-containers/configuration-qemu.toml"
EOF
    log_success "kata-qemu runtime added to containerd"
fi

# Restart containerd
log_info "Restarting containerd..."
systemctl restart containerd || error_exit "Failed to restart containerd"
sleep 3

if systemctl is-active --quiet containerd; then
    log_success "containerd restarted successfully"
else
    error_exit "containerd failed to start. Check: journalctl -u containerd"
fi

log_success "Phase 4 complete"
echo ""

################################################################################
# Phase 5: Verification
################################################################################

log_info "Phase 5: Verifying installation..."

# Check Kata runtime
log_info "Checking Kata runtime..."
if kata-runtime kata-check 2>&1 | grep -q "System is capable"; then
    log_success "Kata runtime check passed"
else
    log_warn "Kata runtime check had warnings (may be OK for nested virt)"
fi

# Check containerd runtime
log_info "Checking containerd runtime registration..."
if crictl --runtime-endpoint unix:///run/containerd/containerd.sock info 2>/dev/null | grep -q "kata"; then
    log_success "Kata runtime visible in containerd"
else
    log_info "Kata runtime may not be visible yet (this can be normal)"
fi

# List installed components
log_info "Installed Kata components:"
ls -lh "${INSTALL_DIR}/bin/" | grep -E "kata-runtime|qemu-system|containerd-shim" || true

log_success "Phase 5 complete"
echo ""

################################################################################
# Installation Summary
################################################################################

log_success "========================================"
log_success "Installation Complete!"
log_success "========================================"
echo ""
log_info "Installed components:"
log_info "  - Kata Containers ${KATA_VERSION}"
log_info "  - VMM: QEMU (via Kata)"
log_info "  - Runtime: kata-qemu (in containerd)"
echo ""
log_info "Key files:"
log_info "  - Kata binaries: ${INSTALL_DIR}/bin/"
log_info "  - Kata config: /etc/kata-containers/configuration-qemu.toml"
log_info "  - Containerd config: ${CONTAINERD_CONFIG}"
log_info "  - Backup: ${CONTAINERD_CONFIG}.backup-pre-kata-qemu"
echo ""
log_info "Next steps:"
log_info "  1. Create RuntimeClass: kubectl apply -f ../manifests/runtimeclass-kata-qemu.yaml"
log_info "  2. Deploy test pod: kubectl apply -f ../manifests/nginx-kata-qemu-test.yaml"
log_info "  3. Verify: kubectl get pods -o wide"
echo ""
log_info "To disable Kata on this node:"
log_info "  sudo ./disable-kata-qemu.sh"
echo ""
log_info "To re-enable Kata on this node:"
log_info "  sudo ./enable-kata-qemu.sh"
echo ""

exit 0
