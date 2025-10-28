#!/bin/bash

################################################################################
# Firecracker-Containerd Uninstallation Script for k8s-node-1
#
# This script removes all firecracker-containerd components and restores
# the original containerd configuration.
#
# What it does:
#   - Removes Firecracker binaries
#   - Removes devmapper thin pool
#   - Restores original containerd config
#   - Cleans up all Firecracker-related files
#
# Usage:
#   sudo ./uninstall-firecracker-node1.sh
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
INSTALL_DIR="/usr/local/bin"
FC_ROOT="/var/lib/firecracker-containerd"
DEVMAPPER_DIR="/var/lib/containerd/devmapper"
CONTAINERD_CONFIG="/etc/containerd/config.toml"
CONTAINERD_BACKUP="${CONTAINERD_CONFIG}.backup-pre-firecracker"

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

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (use sudo)"
   exit 1
fi

log_info "========================================"
log_info "Firecracker-Containerd Uninstallation"
log_info "========================================"
echo ""

# Confirmation
read -p "This will remove all Firecracker components. Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Uninstallation cancelled"
    exit 0
fi

################################################################################
# Step 1: Stop and disable services
################################################################################

log_info "Step 1: Stopping services..."

# Stop devmapper service if it exists
if systemctl list-unit-files | grep -q firecracker-devmapper.service; then
    log_info "Stopping firecracker-devmapper service..."
    systemctl stop firecracker-devmapper.service || true
    systemctl disable firecracker-devmapper.service || true
    rm -f /etc/systemd/system/firecracker-devmapper.service
    systemctl daemon-reload
    log_success "Firecracker-devmapper service removed"
fi

log_success "Step 1 complete"
echo ""

################################################################################
# Step 2: Remove devmapper thin pool
################################################################################

log_info "Step 2: Removing devmapper thin pool..."

# Remove thin pool
if dmsetup status fc-dev-thinpool &> /dev/null; then
    log_info "Removing devmapper pool..."
    dmsetup remove fc-dev-thinpool || log_warn "Failed to remove thin pool (may be in use)"
    log_success "Devmapper pool removed"
else
    log_info "Devmapper pool not found (already removed?)"
fi

# Detach loop devices
log_info "Detaching loop devices..."
for loop in $(losetup -a | grep "$DEVMAPPER_DIR" | cut -d: -f1); do
    log_info "  Detaching $loop..."
    losetup -d "$loop" || log_warn "Failed to detach $loop"
done
log_success "Loop devices detached"

# Remove devmapper directory
if [[ -d "$DEVMAPPER_DIR" ]]; then
    log_info "Removing devmapper directory..."
    rm -rf "$DEVMAPPER_DIR"
    log_success "Devmapper directory removed"
fi

log_success "Step 2 complete"
echo ""

################################################################################
# Step 3: Restore containerd configuration
################################################################################

log_info "Step 3: Restoring containerd configuration..."

# Restore backup if it exists
if [[ -f "$CONTAINERD_BACKUP" ]]; then
    log_info "Restoring containerd config from backup..."
    cp "$CONTAINERD_BACKUP" "$CONTAINERD_CONFIG"
    log_success "Containerd config restored from backup"
else
    log_warn "No backup found. Removing Firecracker-specific sections..."

    # Remove firecracker runtime section (this is a simple approach)
    if [[ -f "$CONTAINERD_CONFIG" ]]; then
        # Create a temporary file without firecracker sections
        grep -v "firecracker\|fc-dev-thinpool\|Devmapper snapshotter for Firecracker" "$CONTAINERD_CONFIG" > "${CONTAINERD_CONFIG}.tmp" || true
        mv "${CONTAINERD_CONFIG}.tmp" "$CONTAINERD_CONFIG"
        log_success "Removed Firecracker sections from containerd config"
    fi
fi

# Remove firecracker runtime config
if [[ -f /etc/containerd/firecracker-runtime.json ]]; then
    rm -f /etc/containerd/firecracker-runtime.json
    log_success "Removed firecracker runtime config"
fi

# Remove CNI config
if [[ -f /etc/cni/conf.d/fcnet.conflist ]]; then
    rm -f /etc/cni/conf.d/fcnet.conflist
    log_success "Removed Firecracker CNI config"
fi

# Restart containerd
log_info "Restarting containerd..."
systemctl restart containerd || log_error "Failed to restart containerd. Check logs: journalctl -u containerd"

sleep 3

if systemctl is-active --quiet containerd; then
    log_success "containerd restarted successfully"
else
    log_error "containerd failed to start after config restore"
    log_error "Manual intervention may be required"
    exit 1
fi

log_success "Step 3 complete"
echo ""

################################################################################
# Step 4: Remove binaries
################################################################################

log_info "Step 4: Removing binaries..."

for binary in firecracker jailer containerd-shim-aws-firecracker; do
    if [[ -f "${INSTALL_DIR}/${binary}" ]]; then
        rm -f "${INSTALL_DIR}/${binary}"
        log_success "  Removed ${binary}"
    else
        log_info "  ${binary} not found (already removed?)"
    fi
done

log_success "Step 4 complete"
echo ""

################################################################################
# Step 5: Remove Firecracker data
################################################################################

log_info "Step 5: Removing Firecracker data..."

if [[ -d "$FC_ROOT" ]]; then
    FC_SIZE=$(du -sh "$FC_ROOT" 2>/dev/null | cut -f1)
    log_info "Removing ${FC_ROOT} (${FC_SIZE})..."
    rm -rf "$FC_ROOT"
    log_success "Firecracker data removed"
else
    log_info "Firecracker data directory not found"
fi

log_success "Step 5 complete"
echo ""

################################################################################
# Step 6: Cleanup and verification
################################################################################

log_info "Step 6: Final cleanup and verification..."

# Remove Go if it was installed by the install script
# (We'll be conservative and leave Go since it might be used by other things)
log_info "Leaving Go installation intact (may be used by other tools)"

# Clean up any remaining Firecracker processes
if pgrep -x firecracker > /dev/null; then
    log_warn "Found running Firecracker processes. Terminating..."
    pkill -9 firecracker || true
    log_success "Terminated Firecracker processes"
fi

# Verify removal
log_info "Verifying removal..."

ISSUES=0

for binary in firecracker jailer containerd-shim-aws-firecracker; do
    if [[ -f "${INSTALL_DIR}/${binary}" ]]; then
        log_warn "  ${binary} still exists"
        ISSUES=$((ISSUES + 1))
    fi
done

if dmsetup status fc-dev-thinpool &> /dev/null; then
    log_warn "  devmapper pool still exists"
    ISSUES=$((ISSUES + 1))
fi

if [[ -d "$FC_ROOT" ]]; then
    log_warn "  Firecracker data directory still exists"
    ISSUES=$((ISSUES + 1))
fi

if systemctl is-active --quiet containerd; then
    log_success "  containerd is running"
else
    log_error "  containerd is not running!"
    ISSUES=$((ISSUES + 1))
fi

log_success "Step 6 complete"
echo ""

################################################################################
# Uninstallation Summary
################################################################################

if [[ $ISSUES -eq 0 ]]; then
    log_success "========================================"
    log_success "Uninstallation Complete!"
    log_success "========================================"
    echo ""
    log_info "All Firecracker components have been removed."
    log_info "containerd has been restored to its original configuration."
    echo ""
    log_info "Cleaned up:"
    log_info "  - Firecracker binaries"
    log_info "  - Devmapper thin pool"
    log_info "  - Firecracker runtime configuration"
    log_info "  - CNI configuration"
    log_info "  - Firecracker data directory"
    echo ""
    log_success "System is ready for normal Kubernetes operations."
else
    log_warn "========================================"
    log_warn "Uninstallation completed with warnings"
    log_warn "========================================"
    echo ""
    log_warn "Some components could not be fully removed."
    log_warn "Please review the warnings above."
    log_warn "You may need to manually clean up remaining components."
    echo ""
fi

echo ""
log_info "Backup of original containerd config preserved at:"
log_info "  ${CONTAINERD_BACKUP}"
echo ""

exit 0
