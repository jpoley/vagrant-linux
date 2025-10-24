#!/bin/bash
#
# setup-host.sh
# Checks and installs/updates Vagrant, VirtualBox, and Ansible on the host system
# Ensures the host is ready to run the Kubernetes cluster
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Minimum required versions
MIN_VAGRANT_VERSION="2.4.0"
MIN_VBOX_VERSION="7.0.0"
MIN_ANSIBLE_VERSION="2.15.0"

echo -e "${CYAN}======================================================${NC}"
echo -e "${CYAN}  Kubernetes Cluster Host Setup${NC}"
echo -e "${CYAN}  Checking and installing required dependencies${NC}"
echo -e "${CYAN}======================================================${NC}"
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}ERROR: Do not run this script as root/sudo${NC}"
    echo -e "${YELLOW}Run as: ./setup-host.sh${NC}"
    echo -e "${YELLOW}The script will prompt for sudo when needed${NC}"
    exit 1
fi

# Function to compare versions
version_ge() {
    # Returns 0 (true) if $1 >= $2
    printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

# Function to get latest Vagrant version from HashiCorp
get_latest_vagrant_version() {
    curl -s https://releases.hashicorp.com/vagrant/ | grep -oP 'vagrant_\K[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}[1/3] Checking Vagrant${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"

if command -v vagrant &> /dev/null; then
    VAGRANT_VERSION=$(vagrant --version | grep -oP '\d+\.\d+\.\d+')
    echo -e "  Current version: ${CYAN}$VAGRANT_VERSION${NC}"
    echo -e "  Minimum required: ${CYAN}$MIN_VAGRANT_VERSION${NC}"

    if version_ge "$VAGRANT_VERSION" "$MIN_VAGRANT_VERSION"; then
        echo -e "  ${GREEN}✓ Vagrant is installed and meets minimum version${NC}"

        # Check for updates
        echo -e "  Checking for updates..."
        LATEST_VERSION=$(get_latest_vagrant_version 2>/dev/null || echo "unknown")
        if [ "$LATEST_VERSION" != "unknown" ] && [ "$VAGRANT_VERSION" != "$LATEST_VERSION" ]; then
            echo -e "  ${YELLOW}⚠ Newer version available: $LATEST_VERSION${NC}"
            echo -e "  ${YELLOW}Download from: https://www.vagrantup.com/downloads${NC}"
        else
            echo -e "  ${GREEN}✓ Vagrant is up-to-date${NC}"
        fi
    else
        echo -e "  ${RED}✗ Vagrant version is too old${NC}"
        echo -e "  ${YELLOW}Please update Vagrant to at least $MIN_VAGRANT_VERSION${NC}"
        echo -e "  ${YELLOW}Download from: https://www.vagrantup.com/downloads${NC}"
        exit 1
    fi
else
    echo -e "  ${RED}✗ Vagrant is not installed${NC}"
    echo -e ""
    echo -e "  ${YELLOW}Installing Vagrant...${NC}"

    # Download and install Vagrant
    cd /tmp
    LATEST_VERSION=$(get_latest_vagrant_version)
    echo -e "  Downloading Vagrant $LATEST_VERSION..."

    wget -q --show-progress "https://releases.hashicorp.com/vagrant/${LATEST_VERSION}/vagrant_${LATEST_VERSION}-1_amd64.deb"

    echo -e "  Installing Vagrant..."
    sudo dpkg -i "vagrant_${LATEST_VERSION}-1_amd64.deb" || {
        echo -e "${RED}Installation failed, trying to fix dependencies...${NC}"
        sudo apt-get install -f -y
    }

    rm "vagrant_${LATEST_VERSION}-1_amd64.deb"

    if command -v vagrant &> /dev/null; then
        echo -e "  ${GREEN}✓ Vagrant installed successfully${NC}"
    else
        echo -e "  ${RED}✗ Vagrant installation failed${NC}"
        exit 1
    fi
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}[2/3] Checking VirtualBox${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"

if command -v VBoxManage &> /dev/null; then
    VBOX_VERSION=$(VBoxManage --version | grep -oP '^\d+\.\d+\.\d+')
    echo -e "  Current version: ${CYAN}$VBOX_VERSION${NC}"
    echo -e "  Minimum required: ${CYAN}$MIN_VBOX_VERSION${NC}"

    if version_ge "$VBOX_VERSION" "$MIN_VBOX_VERSION"; then
        echo -e "  ${GREEN}✓ VirtualBox is installed and meets minimum version${NC}"

        # Check if kernel modules are available
        if lsmod | grep -q vboxdrv; then
            echo -e "  ${GREEN}✓ VirtualBox kernel modules loaded${NC}"
        else
            echo -e "  ${YELLOW}⚠ VirtualBox kernel modules not loaded${NC}"
            echo -e "  ${YELLOW}Will be loaded by switch-to-virtualbox.sh${NC}"
        fi

        # Check vboxusers group membership
        if groups | grep -q vboxusers; then
            echo -e "  ${GREEN}✓ User is in vboxusers group${NC}"
        else
            echo -e "  ${YELLOW}⚠ User '$(whoami)' not in vboxusers group${NC}"
            echo -e "  ${YELLOW}Adding user to vboxusers group...${NC}"
            sudo usermod -aG vboxusers $(whoami)
            echo -e "  ${GREEN}✓ Added to vboxusers group${NC}"
            echo -e "  ${RED}⚠ You must LOG OUT and LOG BACK IN for this to take effect${NC}"
        fi
    else
        echo -e "  ${RED}✗ VirtualBox version is too old${NC}"
        echo -e "  ${YELLOW}Updating VirtualBox...${NC}"
        sudo apt update
        sudo apt install -y virtualbox
    fi
else
    echo -e "  ${RED}✗ VirtualBox is not installed${NC}"
    echo -e ""
    echo -e "  ${YELLOW}Installing VirtualBox...${NC}"

    sudo apt update
    sudo apt install -y virtualbox virtualbox-dkms virtualbox-ext-pack || {
        echo -e "${YELLOW}Note: virtualbox-ext-pack may require manual acceptance${NC}"
    }

    if command -v VBoxManage &> /dev/null; then
        echo -e "  ${GREEN}✓ VirtualBox installed successfully${NC}"

        # Add user to vboxusers group
        sudo usermod -aG vboxusers $(whoami)
        echo -e "  ${GREEN}✓ Added user to vboxusers group${NC}"
        echo -e "  ${RED}⚠ You must LOG OUT and LOG BACK IN for group membership to take effect${NC}"
    else
        echo -e "  ${RED}✗ VirtualBox installation failed${NC}"
        exit 1
    fi
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}[3/3] Checking Ansible${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"

if command -v ansible &> /dev/null; then
    ANSIBLE_VERSION=$(ansible --version | head -1 | grep -oP '\d+\.\d+\.\d+')
    echo -e "  Current version: ${CYAN}$ANSIBLE_VERSION${NC}"
    echo -e "  Minimum required: ${CYAN}$MIN_ANSIBLE_VERSION${NC}"

    if version_ge "$ANSIBLE_VERSION" "$MIN_ANSIBLE_VERSION"; then
        echo -e "  ${GREEN}✓ Ansible is installed and meets minimum version${NC}"
    else
        echo -e "  ${RED}✗ Ansible version is too old${NC}"
        echo -e "  ${YELLOW}Updating Ansible...${NC}"
        sudo apt update
        sudo apt install -y ansible
    fi
else
    echo -e "  ${RED}✗ Ansible is not installed${NC}"
    echo -e ""
    echo -e "  ${YELLOW}Installing Ansible...${NC}"

    sudo apt update
    sudo apt install -y ansible

    if command -v ansible &> /dev/null; then
        echo -e "  ${GREEN}✓ Ansible installed successfully${NC}"
    else
        echo -e "  ${RED}✗ Ansible installation failed${NC}"
        exit 1
    fi
fi

echo ""
echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN}  ✓ Host setup complete!${NC}"
echo -e "${GREEN}======================================================${NC}"
echo ""

# Summary
echo -e "${CYAN}Installed versions:${NC}"
echo -e "  Vagrant:    $(vagrant --version | grep -oP '\d+\.\d+\.\d+')"
echo -e "  VirtualBox: $(VBoxManage --version | grep -oP '^\d+\.\d+\.\d+')"
echo -e "  Ansible:    $(ansible --version | head -1 | grep -oP '\d+\.\d+\.\d+')"
echo ""

# Check if user needs to re-login
NEED_RELOGIN=false
if ! groups | grep -q vboxusers; then
    NEED_RELOGIN=true
fi

if [ "$NEED_RELOGIN" = true ]; then
    echo -e "${RED}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║           ⚠  ACTION REQUIRED  ⚠                   ║${NC}"
    echo -e "${RED}║                                                    ║${NC}"
    echo -e "${RED}║  You were added to the 'vboxusers' group.         ║${NC}"
    echo -e "${RED}║  You MUST log out and log back in before          ║${NC}"
    echo -e "${RED}║  running the Kubernetes cluster.                  ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
else
    echo -e "${CYAN}Next steps:${NC}"
    echo -e "  1. Switch to VirtualBox hypervisor:"
    echo -e "     ${GREEN}./switch-to-virtualbox.sh${NC}"
    echo ""
    echo -e "  2. Start the Kubernetes cluster:"
    echo -e "     ${GREEN}vagrant up${NC}"
    echo ""
    echo -e "  3. Verify the cluster:"
    echo -e "     ${GREEN}./verify-cluster.sh${NC}"
    echo ""
fi
