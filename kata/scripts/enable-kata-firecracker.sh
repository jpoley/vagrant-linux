#!/bin/bash

################################################################################
# Enable Kata Containers + Firecracker on a Node
#
# This script re-enables Kata runtime on the current node by adding the
# kata-fc runtime configuration back to containerd.
#
# Prerequisites:
#   - Kata must already be installed (via install-kata-firecracker.sh)
#
# Usage:
#   sudo ./enable-kata-firecracker.sh
#
################################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
error_exit() { log_error "$1"; exit 1; }

[[ $EUID -ne 0 ]] && error_exit "Run as root (use sudo)"

log_info "========================================"
log_info "Enabling Kata+Firecracker on this node"
log_info "========================================"
echo ""

# Check if Kata is installed
if [[ ! -f "/opt/kata/bin/kata-runtime" ]]; then
    error_exit "Kata not installed. Run install-kata-firecracker.sh first"
fi

# Check if Kata config exists
if [[ ! -f "/etc/kata-containers/configuration-fc.toml" ]]; then
    error_exit "Kata config not found. Run install-kata-firecracker.sh first"
fi

CONTAINERD_CONFIG="/etc/containerd/config.toml"

# Check if already enabled
if grep -q 'runtimes.kata-fc' "$CONTAINERD_CONFIG"; then
    log_warn "kata-fc runtime already enabled"
    log_info "Nothing to do"
    exit 0
fi

# Backup current config
log_info "Backing up current containerd config..."
cp "$CONTAINERD_CONFIG" "${CONTAINERD_CONFIG}.backup-before-enable-$(date +%Y%m%d-%H%M%S)"

# Add kata-fc runtime
log_info "Adding kata-fc runtime to containerd config..."
cat >> "$CONTAINERD_CONFIG" <<'EOF'

# Kata Containers with Firecracker VMM
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.kata-fc]
  runtime_type = "io.containerd.kata.v2"
  privileged_without_host_devices = true
  pod_annotations = ["io.katacontainers.*"]
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.kata-fc.options]
    ConfigPath = "/etc/kata-containers/configuration-fc.toml"
EOF

# Restart containerd
log_info "Restarting containerd..."
systemctl restart containerd
sleep 3

if systemctl is-active --quiet containerd; then
    log_success "containerd restarted successfully"
else
    log_error "containerd failed to restart"
    log_error "Restoring backup..."
    cp "${CONTAINERD_CONFIG}.backup-before-enable-$(date +%Y%m%d)-"* "$CONTAINERD_CONFIG" 2>/dev/null || true
    systemctl restart containerd
    exit 1
fi

log_success "========================================"
log_success "Kata+Firecracker Enabled"
log_success "========================================"
echo ""
log_info "Pods with runtimeClassName: kata-fc will use Firecracker microVMs"
log_info "To disable: sudo ./disable-kata-firecracker.sh"
echo ""

exit 0
