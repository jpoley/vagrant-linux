#!/bin/bash
#
# switch-to-virtualbox.sh
# Switches the system from KVM to VirtualBox by unloading KVM modules and loading VirtualBox modules
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Switching to VirtualBox Hypervisor${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}ERROR: Do not run this script as root/sudo${NC}"
    echo -e "${YELLOW}Run as: ./switch-to-virtualbox.sh${NC}"
    echo -e "${YELLOW}The script will prompt for sudo when needed${NC}"
    exit 1
fi

# Check if VirtualBox is installed
if ! command -v VBoxManage &> /dev/null; then
    echo -e "${RED}ERROR: VirtualBox is not installed${NC}"
    echo -e "${YELLOW}Install with: sudo apt install virtualbox${NC}"
    exit 1
fi

echo -e "${YELLOW}[1/6]${NC} Checking current hypervisor state..."

# Check if any VMs are running in KVM
if systemctl is-active --quiet libvirtd 2>/dev/null; then
    if virsh list --state-running 2>/dev/null | grep -q running; then
        echo -e "${RED}ERROR: KVM VMs are currently running${NC}"
        echo -e "${YELLOW}Please shut down all KVM VMs first:${NC}"
        virsh list --state-running
        exit 1
    fi
fi

# Show currently loaded modules
echo -e "${BLUE}Current virtualization modules loaded:${NC}"
lsmod | grep -E "(kvm|vbox)" || echo "  None"
echo ""

echo -e "${YELLOW}[2/6]${NC} Unloading VirtualBox modules (to allow clean reload)..."
# First unload VirtualBox modules if loaded (to allow clean switch)
if lsmod | grep -q vboxnetadp; then
    sudo modprobe -r vboxnetadp 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} Unloaded vboxnetadp"
fi

if lsmod | grep -q vboxnetflt; then
    sudo modprobe -r vboxnetflt 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} Unloaded vboxnetflt"
fi

if lsmod | grep -q vboxdrv; then
    sudo modprobe -r vboxdrv 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} Unloaded vboxdrv"
fi

echo -e "${YELLOW}[3/6]${NC} Stopping KVM-related services..."
# Stop libvirt services if running
if systemctl is-active --quiet libvirtd 2>/dev/null; then
    sudo systemctl stop libvirtd 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} Stopped libvirtd"
fi

if systemctl is-active --quiet virtlogd 2>/dev/null; then
    sudo systemctl stop virtlogd 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} Stopped virtlogd"
fi

if systemctl is-active --quiet virtlockd 2>/dev/null; then
    sudo systemctl stop virtlockd 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} Stopped virtlockd"
fi

echo -e "${YELLOW}[4/6]${NC} Unloading KVM kernel modules..."
# Unload KVM modules in the correct order (reverse of dependencies)
if lsmod | grep -q kvm_intel; then
    sudo modprobe -r kvm_intel 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} Unloaded kvm_intel"
fi

if lsmod | grep -q kvm_amd; then
    sudo modprobe -r kvm_amd 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} Unloaded kvm_amd"
fi

if lsmod | grep -q kvm; then
    sudo modprobe -r kvm 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} Unloaded kvm"
fi

echo -e "${YELLOW}[5/6]${NC} Loading VirtualBox kernel modules..."
# Use VirtualBox's own service to properly load modules
if systemctl status vboxdrv.service &>/dev/null; then
    sudo systemctl restart vboxdrv.service || {
        echo -e "${RED}ERROR: Failed to restart vboxdrv service${NC}"
        echo -e "${YELLOW}Trying manual setup...${NC}"
        sudo /usr/lib/virtualbox/vboxdrv.sh setup || {
            echo -e "${RED}ERROR: VirtualBox kernel module setup failed${NC}"
            echo -e "${YELLOW}Try reinstalling VirtualBox kernel modules:${NC}"
            echo -e "${YELLOW}  sudo apt install --reinstall virtualbox-dkms virtualbox${NC}"
            exit 1
        }
    }
else
    # Service doesn't exist, try direct module loading
    sudo modprobe vboxdrv 2>/dev/null || {
        echo -e "${RED}ERROR: Failed to load vboxdrv module${NC}"
        echo -e "${YELLOW}Trying VirtualBox setup script...${NC}"
        sudo /usr/lib/virtualbox/vboxdrv.sh setup || {
            echo -e "${RED}ERROR: VirtualBox setup failed${NC}"
            echo -e "${YELLOW}Try reinstalling: sudo apt install --reinstall virtualbox-dkms virtualbox${NC}"
            exit 1
        }
    }
fi

# Verify modules are loaded
if lsmod | grep -q vboxdrv; then
    echo -e "  ${GREEN}✓${NC} Loaded vboxdrv"
else
    echo -e "${RED}ERROR: vboxdrv module is not loaded${NC}"
    exit 1
fi

if lsmod | grep -q vboxnetflt; then
    echo -e "  ${GREEN}✓${NC} Loaded vboxnetflt"
fi

if lsmod | grep -q vboxnetadp; then
    echo -e "  ${GREEN}✓${NC} Loaded vboxnetadp"
fi

echo -e "${YELLOW}[6/6]${NC} Verifying VirtualBox setup..."

# Check if user is in vboxusers group
if ! groups | grep -q vboxusers; then
    echo -e "${YELLOW}  WARNING: User '$(whoami)' is not in 'vboxusers' group${NC}"
    echo -e "${YELLOW}  Adding user to vboxusers group...${NC}"
    sudo usermod -aG vboxusers $(whoami)
    echo -e "  ${GREEN}✓${NC} Added to vboxusers group"
    echo -e "${RED}  ⚠ You must LOG OUT and LOG BACK IN for group changes to take effect${NC}"
fi

# Test VirtualBox
if VBoxManage list vms &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} VirtualBox is functional"
else
    echo -e "${RED}ERROR: VirtualBox test failed${NC}"
    exit 1
fi

echo -e "${YELLOW}[7/7]${NC} Final verification..."
echo -e "${BLUE}Currently loaded modules:${NC}"
lsmod | grep -E "(kvm|vbox)" | awk '{printf "  %s\n", $1}'
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  ✓ Successfully switched to VirtualBox${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}You can now run:${NC}"
echo -e "  ${GREEN}vagrant up${NC}"
echo ""
echo -e "${BLUE}To switch back to KVM:${NC}"
echo -e "  ${GREEN}./switch-to-kvm.sh${NC}"
echo ""

# Check if user needs to re-login
if ! groups | grep -q vboxusers; then
    echo -e "${RED}⚠⚠⚠ IMPORTANT ⚠⚠⚠${NC}"
    echo -e "${YELLOW}You were just added to the 'vboxusers' group.${NC}"
    echo -e "${YELLOW}You MUST log out and log back in before using VirtualBox.${NC}"
    echo ""
fi
