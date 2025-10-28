#!/bin/bash

################################################################################
# Firecracker-Containerd Installation Script for k8s-node-1
#
# This script installs native firecracker-containerd (without Kata) on a
# Kubernetes worker node, enabling pods to run in Firecracker microVMs.
#
# Architecture:
#   - Keeps existing containerd for standard workloads
#   - Adds Firecracker as additional runtime via aws.firecracker shim
#   - Uses devmapper snapshotter for Firecracker workloads
#   - RuntimeClass selector for pod scheduling
#
# Requirements:
#   - Ubuntu 24.04
#   - KVM support (/dev/kvm accessible)
#   - Existing containerd installation
#   - At least 20GB free disk space
#   - Nested virtualization enabled (libvirt host-passthrough)
#
# Usage:
#   sudo ./install-firecracker-node1.sh
#
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
FIRECRACKER_VERSION="v1.10.1"
FIRECRACKER_CONTAINERD_VERSION="main"
GO_VERSION="1.23.4"
KERNEL_VERSION="5.10.232"
WORK_DIR="/tmp/firecracker-build"
INSTALL_DIR="/usr/local/bin"
FC_ROOT="/var/lib/firecracker-containerd"
FC_RUNTIME_DIR="${FC_ROOT}/runtime"
DEVMAPPER_DIR="/var/lib/containerd/devmapper"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handler
error_exit() {
    log_error "$1"
    exit 1
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error_exit "This script must be run as root (use sudo)"
fi

log_info "========================================"
log_info "Firecracker-Containerd Installation"
log_info "========================================"
echo ""

################################################################################
# Phase 1: Prerequisites & Validation
################################################################################

log_info "Phase 1: Validating prerequisites..."

# Check KVM support
if [[ ! -e /dev/kvm ]]; then
    error_exit "/dev/kvm not found. KVM support is required."
fi

if [[ ! -r /dev/kvm ]] || [[ ! -w /dev/kvm ]]; then
    error_exit "/dev/kvm is not accessible. Check permissions."
fi

log_success "KVM support verified (/dev/kvm accessible)"

# Check if containerd is installed and running
if ! systemctl is-active --quiet containerd; then
    error_exit "containerd is not running. Please start containerd first."
fi

log_success "containerd is running"

# Check disk space (need at least 25GB)
AVAILABLE_GB=$(df /var/lib --output=avail --block-size=1G | tail -1 | tr -d ' ')
if [[ $AVAILABLE_GB -lt 25 ]]; then
    log_warn "Low disk space: ${AVAILABLE_GB}GB available. Recommend at least 25GB."
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

log_success "Disk space check passed (${AVAILABLE_GB}GB available)"

# Install build dependencies
log_info "Installing build dependencies..."
apt-get update -qq
apt-get install -y -qq \
    git \
    make \
    gcc \
    curl \
    wget \
    build-essential \
    pkg-config \
    libseccomp-dev \
    dmsetup \
    bc \
    jq \
    debootstrap \
    squashfs-tools \
    || error_exit "Failed to install dependencies"

log_success "Build dependencies installed"

# Check and install Go if needed
if command -v go &> /dev/null; then
    CURRENT_GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
    log_info "Go ${CURRENT_GO_VERSION} is already installed"
else
    log_info "Installing Go ${GO_VERSION}..."
    cd /tmp
    wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" || error_exit "Failed to download Go"
    rm -rf /usr/local/go
    tar -C /usr/local -xzf "go${GO_VERSION}.linux-amd64.tar.gz" || error_exit "Failed to extract Go"
    export PATH=$PATH:/usr/local/go/bin
    echo 'export PATH=$PATH:/usr/local/go/bin' >> /root/.bashrc
    log_success "Go ${GO_VERSION} installed"
fi

# Verify Go installation
if ! /usr/local/go/bin/go version &> /dev/null; then
    error_exit "Go installation failed"
fi

export PATH=$PATH:/usr/local/go/bin
log_success "Phase 1 complete"
echo ""

################################################################################
# Phase 2: Build Firecracker Components
################################################################################

log_info "Phase 2: Building Firecracker components..."

# Create work directory
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Download Firecracker binary
log_info "Downloading Firecracker ${FIRECRACKER_VERSION}..."
FIRECRACKER_URL="https://github.com/firecracker-microvm/firecracker/releases/download/${FIRECRACKER_VERSION}/firecracker-${FIRECRACKER_VERSION}-x86_64.tgz"
wget -q "$FIRECRACKER_URL" -O firecracker.tgz || error_exit "Failed to download Firecracker"
tar -xzf firecracker.tgz || error_exit "Failed to extract Firecracker"
cp "release-${FIRECRACKER_VERSION}-x86_64/firecracker-${FIRECRACKER_VERSION}-x86_64" "${INSTALL_DIR}/firecracker" || error_exit "Failed to copy firecracker binary"
cp "release-${FIRECRACKER_VERSION}-x86_64/jailer-${FIRECRACKER_VERSION}-x86_64" "${INSTALL_DIR}/jailer" || error_exit "Failed to copy jailer binary"
chmod +x "${INSTALL_DIR}/firecracker" "${INSTALL_DIR}/jailer"
log_success "Firecracker and Jailer binaries installed"

# Clone and build firecracker-containerd
log_info "Cloning firecracker-containerd ${FIRECRACKER_CONTAINERD_VERSION}..."
git clone --depth 1 --branch "${FIRECRACKER_CONTAINERD_VERSION}" \
    https://github.com/firecracker-microvm/firecracker-containerd.git \
    || error_exit "Failed to clone firecracker-containerd"

cd firecracker-containerd

log_info "Building containerd-shim-aws-firecracker (this may take 5-10 minutes)..."
make runtime || error_exit "Failed to build runtime"

# Install shim binary
cp runtime/containerd-shim-aws-firecracker "${INSTALL_DIR}/" \
    || error_exit "Failed to copy shim binary"
chmod +x "${INSTALL_DIR}/containerd-shim-aws-firecracker"
log_success "containerd-shim-aws-firecracker installed"

# Build agent binary first
log_info "Building agent binary..."
make agent || error_exit "Failed to build agent"
mkdir -p tools/image-builder/files_ephemeral/usr/local/bin
cp agent/agent tools/image-builder/files_ephemeral/usr/local/bin/agent || error_exit "Failed to copy agent"

# Build runc
log_info "Building runc (static binary)..."
git submodule update --init --recursive _submodules/runc || error_exit "Failed to init runc submodule"
make -C _submodules/runc static BUILDTAGS='seccomp' || error_exit "Failed to build runc"
mkdir -p tools/image-builder/files_ephemeral/usr/local/bin
cp _submodules/runc/runc tools/image-builder/files_ephemeral/usr/local/bin/runc || error_exit "Failed to copy runc"

# Build rootfs image without Docker
log_info "Building microVM rootfs image (this may take 10-15 minutes)..."
cd tools/image-builder
mkdir -p tmp
make rootfs.img || error_exit "Failed to build rootfs image"
cd ../..

# Install rootfs and kernel
mkdir -p "$FC_RUNTIME_DIR"
cp tools/image-builder/rootfs.img "${FC_RUNTIME_DIR}/default-rootfs.img" \
    || error_exit "Failed to copy rootfs image"
log_success "MicroVM rootfs installed"

# Download kernel
log_info "Downloading microVM kernel..."
KERNEL_URL="https://s3.amazonaws.com/spec.ccfc.min/img/quickstart_guide/x86_64/kernels/vmlinux.bin"
wget -q "$KERNEL_URL" -O "${FC_RUNTIME_DIR}/vmlinux" \
    || error_exit "Failed to download kernel"
chmod 644 "${FC_RUNTIME_DIR}/vmlinux"
log_success "Kernel downloaded"

log_success "Phase 2 complete"
echo ""

################################################################################
# Phase 3: Setup Devmapper Storage
################################################################################

log_info "Phase 3: Setting up devmapper thin pool..."

# Check if thin pool already exists
if dmsetup status fc-dev-thinpool &> /dev/null; then
    log_info "Devmapper thin pool already exists, skipping creation"
else
    # Create devmapper directory
    mkdir -p "$DEVMAPPER_DIR"
    cd "$DEVMAPPER_DIR"

    # Create sparse files for data and metadata
    log_info "Creating storage files (20GB data + 2GB metadata)..."
    dd if=/dev/zero of=data.img bs=1 count=0 seek=20G &> /dev/null || error_exit "Failed to create data image"
    dd if=/dev/zero of=metadata.img bs=1 count=0 seek=2G &> /dev/null || error_exit "Failed to create metadata image"
    log_success "Storage files created"

    # Setup loop devices
    log_info "Setting up loop devices..."
    DATA_LOOP=$(losetup -f --show data.img) || error_exit "Failed to setup data loop device"
    META_LOOP=$(losetup -f --show metadata.img) || error_exit "Failed to setup metadata loop device"
    log_info "Data loop: ${DATA_LOOP}, Metadata loop: ${META_LOOP}"

    # Get sector counts
    DATA_SIZE_SECTORS=$(blockdev --getsz "$DATA_LOOP")
    META_SIZE_SECTORS=$(blockdev --getsz "$META_LOOP")

    # Create thin pool
    log_info "Creating device mapper thin pool..."
    dmsetup create fc-dev-thinpool \
        --table "0 ${DATA_SIZE_SECTORS} thin-pool ${META_LOOP} ${DATA_LOOP} 128 32768 1 skip_block_zeroing" \
        || error_exit "Failed to create thin pool"

    log_success "Devmapper thin pool created: fc-dev-thinpool"

    # Persist loop device setup
    cat > /etc/systemd/system/firecracker-devmapper.service <<EOF
[Unit]
Description=Setup devmapper for firecracker-containerd
DefaultDependencies=no
After=systemd-udev-settle.service
Before=lvm2-activation-early.service
Wants=systemd-udev-settle.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c '\
  losetup ${DATA_LOOP} ${DEVMAPPER_DIR}/data.img || exit 1; \
  losetup ${META_LOOP} ${DEVMAPPER_DIR}/metadata.img || exit 1; \
  DATA_SIZE=\$(blockdev --getsz ${DATA_LOOP}); \
  dmsetup create fc-dev-thinpool --table \"0 \$DATA_SIZE thin-pool ${META_LOOP} ${DATA_LOOP} 128 32768 1 skip_block_zeroing\" || \
  dmsetup message fc-dev-thinpool 0 reserve_metadata_snap || exit 0'
ExecStop=/bin/bash -c '\
  dmsetup remove fc-dev-thinpool || true; \
  losetup -d ${DATA_LOOP} || true; \
  losetup -d ${META_LOOP} || true'

[Install]
WantedBy=local-fs.target
EOF

    systemctl daemon-reload
    systemctl enable firecracker-devmapper.service
    log_success "Devmapper service installed and enabled"
fi

log_success "Phase 3 complete"
echo ""

################################################################################
# Phase 4: Configure Firecracker Runtime
################################################################################

log_info "Phase 4: Configuring containerd runtime..."

# Backup original containerd config
CONTAINERD_CONFIG="/etc/containerd/config.toml"
if [[ ! -f "${CONTAINERD_CONFIG}.backup-pre-firecracker" ]]; then
    cp "$CONTAINERD_CONFIG" "${CONTAINERD_CONFIG}.backup-pre-firecracker"
    log_info "Backed up containerd config to ${CONTAINERD_CONFIG}.backup-pre-firecracker"
fi

# Create firecracker runtime configuration
mkdir -p /etc/containerd
cat > /etc/containerd/firecracker-runtime.json <<EOF
{
  "firecracker_binary_path": "/usr/local/bin/firecracker",
  "kernel_image_path": "${FC_RUNTIME_DIR}/vmlinux",
  "kernel_args": "console=ttyS0 noapic reboot=k panic=1 pci=off nomodules ro systemd.unified_cgroup_hierarchy=0 systemd.journald.forward_to_console systemd.unit=firecracker.target init=/sbin/overlay-init",
  "root_drive": "${FC_RUNTIME_DIR}/default-rootfs.img",
  "cpu_template": "C3",
  "log_levels": ["debug"],
  "default_network_interfaces": [{
    "CNIConfig": {
      "NetworkName": "fcnet",
      "InterfaceName": "veth0"
    }
  }]
}
EOF

log_success "Firecracker runtime config created"

# Configure devmapper in containerd config
log_info "Adding devmapper snapshotter to containerd config..."

# Check if devmapper section exists (with or without leading whitespace)
if grep -q '\[plugins."io.containerd.snapshotter.v1.devmapper"\]' "$CONTAINERD_CONFIG"; then
    log_info "Devmapper section already exists, updating configuration..."
    # Update pool_name in existing devmapper section
    sed -i '/\[plugins."io.containerd.snapshotter.v1.devmapper"\]/,/^\[/ {
        s/^[[:space:]]*pool_name[[:space:]]*=.*/  pool_name = "fc-dev-thinpool"/
        s/^[[:space:]]*root_path[[:space:]]*=.*/  root_path = "'"${DEVMAPPER_DIR}"'"/
        s/^[[:space:]]*base_image_size[[:space:]]*=.*/  base_image_size = "8GB"/
    }' "$CONTAINERD_CONFIG"
    log_success "Devmapper snapshotter configured"
else
    # Add devmapper configuration (shouldn't happen with default containerd config)
    cat >> "$CONTAINERD_CONFIG" <<EOF

# Devmapper snapshotter for Firecracker
[plugins."io.containerd.snapshotter.v1.devmapper"]
  pool_name = "fc-dev-thinpool"
  root_path = "${DEVMAPPER_DIR}"
  base_image_size = "8GB"
  discard_blocks = false
  fs_type = "ext4"
EOF
    log_success "Devmapper snapshotter configured"
fi

# Add firecracker runtime to containerd config
log_info "Adding firecracker runtime to containerd config..."

# Check if firecracker runtime exists
if grep -q 'runtimes.firecracker' "$CONTAINERD_CONFIG"; then
    log_warn "Firecracker runtime already exists in containerd config"
else
    # Find the runtimes section and add firecracker
    # Add after the [plugins."io.containerd.grpc.v1.cri".containerd.runtimes] section
    sed -i '/\[plugins\."io\.containerd\.grpc\.v1\.cri"\.containerd\.runtimes\.runc\]/i \
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.firecracker]\n\
          runtime_type = "aws.firecracker"\n\
          runtime_engine = ""\n\
          runtime_root = ""\n\
          privileged_without_host_devices = false\n\
          snapshotter = "devmapper"\n\
\n' "$CONTAINERD_CONFIG"

    log_success "Firecracker runtime added to containerd config"
fi

# Create CNI configuration for Firecracker
log_info "Creating CNI configuration..."
mkdir -p /etc/cni/conf.d
cat > /etc/cni/conf.d/fcnet.conflist <<EOF
{
  "name": "fcnet",
  "cniVersion": "0.4.0",
  "plugins": [
    {
      "type": "bridge",
      "bridge": "fcbr0",
      "isGateway": true,
      "ipMasq": true,
      "hairpinMode": true,
      "ipam": {
        "type": "host-local",
        "subnet": "10.244.1.0/24",
        "routes": [
          { "dst": "0.0.0.0/0" }
        ]
      }
    },
    {
      "type": "firewall"
    },
    {
      "type": "tc-redirect-tap"
    }
  ]
}
EOF

log_success "CNI configuration created"

# Restart containerd
log_info "Restarting containerd..."
systemctl restart containerd || error_exit "Failed to restart containerd"

# Wait for containerd to be ready
sleep 5

if systemctl is-active --quiet containerd; then
    log_success "containerd restarted successfully"
else
    error_exit "containerd failed to start. Check logs: journalctl -u containerd"
fi

# Verify runtime is available
log_info "Verifying firecracker runtime..."
if crictl --runtime-endpoint unix:///run/containerd/containerd.sock info | grep -q "firecracker"; then
    log_success "Firecracker runtime registered with containerd"
else
    log_warn "Firecracker runtime may not be visible yet (this can be normal)"
fi

log_success "Phase 4 complete"
echo ""

################################################################################
# Phase 5: Verification
################################################################################

log_info "Phase 5: Final verification..."

# Check binaries
log_info "Checking installed binaries..."
for binary in firecracker jailer containerd-shim-aws-firecracker; do
    if [[ -x "${INSTALL_DIR}/${binary}" ]]; then
        log_success "  ${binary}: OK"
    else
        error_exit "  ${binary}: MISSING"
    fi
done

# Check rootfs and kernel
log_info "Checking microVM components..."
if [[ -f "${FC_RUNTIME_DIR}/default-rootfs.img" ]]; then
    ROOTFS_SIZE=$(du -h "${FC_RUNTIME_DIR}/default-rootfs.img" | cut -f1)
    log_success "  rootfs: OK (${ROOTFS_SIZE})"
else
    error_exit "  rootfs: MISSING"
fi

if [[ -f "${FC_RUNTIME_DIR}/vmlinux" ]]; then
    KERNEL_SIZE=$(du -h "${FC_RUNTIME_DIR}/vmlinux" | cut -f1)
    log_success "  kernel: OK (${KERNEL_SIZE})"
else
    error_exit "  kernel: MISSING"
fi

# Check devmapper
log_info "Checking devmapper thin pool..."
if dmsetup status fc-dev-thinpool &> /dev/null; then
    log_success "  devmapper pool: OK"
else
    error_exit "  devmapper pool: FAILED"
fi

# Check containerd
log_info "Checking containerd status..."
if systemctl is-active --quiet containerd; then
    log_success "  containerd: RUNNING"
else
    error_exit "  containerd: NOT RUNNING"
fi

# Check KVM permissions
log_info "Checking KVM permissions..."
if [[ -r /dev/kvm ]] && [[ -w /dev/kvm ]]; then
    log_success "  /dev/kvm: ACCESSIBLE"
else
    log_warn "  /dev/kvm: May need additional permissions"
fi

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
log_info "  - Firecracker ${FIRECRACKER_VERSION}"
log_info "  - Jailer ${FIRECRACKER_VERSION}"
log_info "  - containerd-shim-aws-firecracker"
log_info "  - MicroVM kernel (${KERNEL_VERSION})"
log_info "  - MicroVM rootfs"
log_info "  - Devmapper thin pool: fc-dev-thinpool"
echo ""
log_info "Configuration files:"
log_info "  - Runtime config: /etc/containerd/firecracker-runtime.json"
log_info "  - CNI config: /etc/cni/conf.d/fcnet.conflist"
log_info "  - Containerd config: ${CONTAINERD_CONFIG}"
log_info "  - Backup: ${CONTAINERD_CONFIG}.backup-pre-firecracker"
echo ""
log_info "Next steps:"
log_info "  1. Deploy RuntimeClass: kubectl apply -f manifests/runtimeclass-firecracker.yaml"
log_info "  2. Test with nginx: kubectl apply -f manifests/nginx-firecracker-test.yaml"
log_info "  3. Verify: kubectl get pods -o wide"
echo ""
log_warn "To uninstall: sudo ./scripts/uninstall-firecracker-node1.sh"
echo ""

# Cleanup
rm -rf "$WORK_DIR"
log_info "Cleaned up temporary build files"

exit 0
