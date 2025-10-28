#!/bin/bash

################################################################################
# Disable Kata Containers + Firecracker on a Node
#
# This script disables Kata runtime on the current node by removing the
# kata-fc runtime configuration from containerd. Kata binaries remain installed
# for quick re-enabling.
#
# Usage:
#   sudo ./disable-kata-firecracker.sh
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

[[ $EUID -ne 0 ]] && { log_error "Run as root (use sudo)"; exit 1; }

log_info "========================================"
log_info "Disabling Kata+Firecracker on this node"
log_info "========================================"
echo ""

CONTAINERD_CONFIG="/etc/containerd/config.toml"

# Check if kata-fc exists
if ! grep -q 'runtimes.kata-fc' "$CONTAINERD_CONFIG"; then
    log_warn "kata-fc runtime not found in containerd config"
    log_info "Nothing to disable"
    exit 0
fi

# Backup current config
log_info "Backing up current containerd config..."
cp "$CONTAINERD_CONFIG" "${CONTAINERD_CONFIG}.backup-before-disable-$(date +%Y%m%d-%H%M%S)"

# Remove kata-fc runtime section
log_info "Removing kata-fc runtime from containerd config..."
sed -i '/# Kata Containers with Firecracker VMM/,/ConfigPath = "\/etc\/kata-containers\/configuration-fc.toml"/d' "$CONTAINERD_CONFIG"

# Restart containerd
log_info "Restarting containerd..."
systemctl restart containerd
sleep 3

if systemctl is-active --quiet containerd; then
    log_success "containerd restarted successfully"
else
    log_error "containerd failed to restart"
    log_error "Restoring backup..."
    cp "${CONTAINERD_CONFIG}.backup-before-disable-$(date +%Y%m%d)-"* "$CONTAINERD_CONFIG" 2>/dev/null || true
    systemctl restart containerd
    exit 1
fi

log_success "========================================"
log_success "Kata+Firecracker Disabled"
log_success "========================================"
echo ""
log_info "Kata binaries remain installed in /opt/kata"
log_info "To re-enable: sudo ./enable-kata-firecracker.sh"
echo ""

exit 0
