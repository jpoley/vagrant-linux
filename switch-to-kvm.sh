#!/bin/bash
#
# switch-to-kvm.sh
# Switches the system from VirtualBox to KVM by unloading VirtualBox modules and loading KVM modules
# This is needed for running KVM-based applications like Slicer
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Switching to KVM Hypervisor${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}ERROR: Do not run this script as root/sudo${NC}"
    echo -e "${YELLOW}Run as: ./switch-to-kvm.sh${NC}"
    echo -e "${YELLOW}The script will prompt for sudo when needed${NC}"
    exit 1
fi

# Check if KVM is installed
if ! command -v virsh &> /dev/null; then
    echo -e "${YELLOW}WARNING: libvirt tools are not installed${NC}"
    echo -e "${YELLOW}KVM modules will still be loaded, but libvirt won't be available${NC}"
    echo -e "${YELLOW}To install: sudo apt install qemu-kvm libvirt-daemon-system${NC}"
    echo ""
fi

echo -e "${YELLOW}[1/6]${NC} Checking current hypervisor state..."

# Check if any VMs are running in VirtualBox
if command -v VBoxManage &> /dev/null; then
    RUNNING_VMS=$(VBoxManage list runningvms 2>/dev/null || true)
    if [ ! -z "$RUNNING_VMS" ]; then
        echo -e "${RED}ERROR: VirtualBox VMs are currently running${NC}"
        echo -e "${YELLOW}Please shut down all VirtualBox VMs first:${NC}"
        echo "$RUNNING_VMS"
        echo ""
        echo -e "${YELLOW}Run: vagrant halt${NC}"
        exit 1
    fi
fi

# Show currently loaded modules
echo -e "${BLUE}Current virtualization modules loaded:${NC}"
lsmod | grep -E "(kvm|vbox)" || echo "  None"
echo ""

echo -e "${YELLOW}[2/6]${NC} Unloading VirtualBox kernel modules..."
# Unload VirtualBox modules in the correct order (reverse of dependencies)
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

echo -e "${YELLOW}[3/6]${NC} Loading KVM kernel modules..."
# Load KVM modules
CPU_VENDOR=$(lscpu | grep "Vendor ID" | awk '{print $3}')

if [ "$CPU_VENDOR" = "GenuineIntel" ]; then
    sudo modprobe kvm_intel 2>/dev/null || {
        echo -e "${RED}ERROR: Failed to load kvm_intel module${NC}"
        echo -e "${YELLOW}Your CPU may not support virtualization or it's disabled in BIOS${NC}"
        exit 1
    }
    echo -e "  ${GREEN}✓${NC} Loaded kvm_intel (Intel CPU detected)"
elif [ "$CPU_VENDOR" = "AuthenticAMD" ]; then
    sudo modprobe kvm_amd 2>/dev/null || {
        echo -e "${RED}ERROR: Failed to load kvm_amd module${NC}"
        echo -e "${YELLOW}Your CPU may not support virtualization or it's disabled in BIOS${NC}"
        exit 1
    }
    echo -e "  ${GREEN}✓${NC} Loaded kvm_amd (AMD CPU detected)"
else
    echo -e "${RED}ERROR: Unknown CPU vendor: $CPU_VENDOR${NC}"
    exit 1
fi

# The base kvm module should be loaded automatically as a dependency
if lsmod | grep -q "^kvm"; then
    echo -e "  ${GREEN}✓${NC} Loaded kvm (base module)"
else
    echo -e "${RED}ERROR: KVM base module failed to load${NC}"
    exit 1
fi

echo -e "${YELLOW}[4/6]${NC} Starting KVM-related services..."
# Start libvirt services if installed
if command -v virsh &> /dev/null; then
    if systemctl list-unit-files | grep -q libvirtd; then
        sudo systemctl start libvirtd 2>/dev/null || true
        echo -e "  ${GREEN}✓${NC} Started libvirtd"
    fi

    if systemctl list-unit-files | grep -q virtlogd; then
        sudo systemctl start virtlogd 2>/dev/null || true
        echo -e "  ${GREEN}✓${NC} Started virtlogd"
    fi

    if systemctl list-unit-files | grep -q virtlockd; then
        sudo systemctl start virtlockd 2>/dev/null || true
        echo -e "  ${GREEN}✓${NC} Started virtlockd"
    fi
else
    echo -e "  ${YELLOW}⊘${NC} libvirt not installed (skipping service start)"
fi

echo -e "${YELLOW}[5/6]${NC} Verifying KVM setup..."

# Check /dev/kvm exists
if [ -e /dev/kvm ]; then
    echo -e "  ${GREEN}✓${NC} /dev/kvm exists"
else
    echo -e "${RED}ERROR: /dev/kvm does not exist${NC}"
    exit 1
fi

# Check user has access to KVM
if groups | grep -q libvirt || groups | grep -q kvm; then
    echo -e "  ${GREEN}✓${NC} User has KVM access (member of libvirt or kvm group)"
else
    echo -e "${YELLOW}  WARNING: User '$(whoami)' is not in 'libvirt' or 'kvm' group${NC}"
    echo -e "${YELLOW}  You may not be able to use KVM without sudo${NC}"
    if grep -q "^libvirt:" /etc/group; then
        echo -e "${YELLOW}  Consider adding yourself: sudo usermod -aG libvirt $(whoami)${NC}"
    elif grep -q "^kvm:" /etc/group; then
        echo -e "${YELLOW}  Consider adding yourself: sudo usermod -aG kvm $(whoami)${NC}"
    fi
fi

# Test KVM if virsh is available
if command -v virsh &> /dev/null; then
    if virsh list &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} KVM/libvirt is functional"
    else
        echo -e "${YELLOW}  ⊘${NC} KVM modules loaded but libvirt test failed (may need group membership)"
    fi
fi

echo -e "${YELLOW}[6/6]${NC} Final verification..."
echo -e "${BLUE}Currently loaded modules:${NC}"
lsmod | grep -E "(kvm|vbox)" | awk '{printf "  %s\n", $1}'
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  ✓ Successfully switched to KVM${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}KVM is now active and ready for:${NC}"
echo -e "  • Slicer"
echo -e "  • virt-manager"
echo -e "  • libvirt-based VMs"
echo -e "  • Other KVM applications"
echo ""
echo -e "${BLUE}To switch back to VirtualBox (for Kubernetes cluster):${NC}"
echo -e "  ${GREEN}./switch-to-virtualbox.sh${NC}"
echo ""
