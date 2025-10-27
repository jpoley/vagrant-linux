# Migration Plan: VirtualBox → vagrant-libvirt (KVM/QEMU)

**Date Created:** 2025-10-27
**Status:** Planning Phase
**Complexity Assessment:** MODERATE
**Impact:** Multiple files, provider-specific configuration changes required

---

## Table of Contents
1. [Executive Summary](#executive-summary)
2. [Understanding the Current State](#understanding-the-current-state)
3. [Chain of Thought Analysis](#chain-of-thought-analysis)
4. [Technical Deep Dive](#technical-deep-dive)
5. [Migration Impact Assessment](#migration-impact-assessment)
6. [Step-by-Step Migration Plan](#step-by-step-migration-plan)
7. [Nuances and Gotchas](#nuances-and-gotchas)
8. [Testing and Validation](#testing-and-validation)
9. [Rollback Plan](#rollback-plan)

---

## Executive Summary

### What We're Doing
Migrating from VirtualBox to vagrant-libvirt as the Vagrant provider, switching from Oracle's VirtualBox hypervisor to KVM/QEMU (Linux's native virtualization).

### Why This Matters
- **Current**: Vagrant uses VirtualBox provider → VirtualBox kernel modules → VirtualBox hypervisor
- **Goal**: Vagrant uses libvirt provider → KVM kernel modules → QEMU/KVM hypervisor
- **Benefit**: Native Linux virtualization, better performance, no license concerns

### Complexity Level: MODERATE

**Why MODERATE and not SIMPLE:**
1. Provider configuration syntax is different
2. Networking configuration requires careful translation
3. Multiple files need coordinated changes
4. Box compatibility must be verified
5. System dependencies change significantly
6. Group membership and permissions differ

**Why MODERATE and not COMPLEX:**
1. No application code changes needed
2. Ansible playbooks are provider-agnostic (no changes needed)
3. VM guest configurations remain identical
4. Network topology stays the same
5. No data migration required

---

## Understanding the Current State

### Current Architecture (Two Layers)

```
┌─────────────────────────────────────────────────────────────────┐
│                         HOST SYSTEM                              │
│                        Ubuntu 24.04                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ╔══════════════════════════════════════════════════════════╗  │
│  ║ LAYER 2: Vagrant Provider (what we need to change)      ║  │
│  ╚══════════════════════════════════════════════════════════╝  │
│                                                                   │
│  ┌──────────────┐     ┌──────────────────────────────────────┐  │
│  │   Vagrant    │────▶│  VirtualBox Provider (current)       │  │
│  │              │     │  - Lines 40-46 in Vagrantfile        │  │
│  └──────────────┘     └──────────────────────────────────────┘  │
│                                │                                 │
│  ╔══════════════════════════════════════════════════════════╗  │
│  ║ LAYER 1: Kernel Modules (switch-to-kvm.sh handles this) ║  │
│  ╚══════════════════════════════════════════════════════════╝  │
│                                │                                 │
│                                ▼                                 │
│                       ┌────────────────┐                         │
│                       │  VirtualBox    │                         │
│                       │  Hypervisor    │                         │
│                       └────────────────┘                         │
│                                │                                 │
│                       ┌────────┴────────┐                        │
│                       ▼                 ▼                        │
│              Kernel Modules:    vboxdrv, vboxnetflt,             │
│                                 vboxnetadp                       │
└─────────────────────────────────────────────────────────────────┘
```

### Target Architecture (After Migration)

```
┌─────────────────────────────────────────────────────────────────┐
│                         HOST SYSTEM                              │
│                        Ubuntu 24.04                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ╔══════════════════════════════════════════════════════════╗  │
│  ║ LAYER 2: Vagrant Provider (THIS MIGRATION)              ║  │
│  ╚══════════════════════════════════════════════════════════╝  │
│                                                                   │
│  ┌──────────────┐     ┌──────────────────────────────────────┐  │
│  │   Vagrant    │────▶│  libvirt Provider (NEW)              │  │
│  │              │     │  - vagrant-libvirt plugin            │  │
│  └──────────────┘     └──────────────────────────────────────┘  │
│                                │                                 │
│  ╔══════════════════════════════════════════════════════════╗  │
│  ║ LAYER 1: Kernel Modules (switch-to-kvm.sh DONE!)        ║  │
│  ╚══════════════════════════════════════════════════════════╝  │
│                                │                                 │
│                                ▼                                 │
│                       ┌────────────────┐                         │
│                       │  libvirt       │                         │
│                       │  + QEMU/KVM    │                         │
│                       └────────────────┘                         │
│                                │                                 │
│                       ┌────────┴────────┐                        │
│                       ▼                 ▼                        │
│              Kernel Modules:    kvm_intel/kvm_amd, kvm           │
└─────────────────────────────────────────────────────────────────┘
```

### Current Vagrantfile Provider Block (Lines 40-46)

```ruby
# Provider configuration - VirtualBox for Linux
node_config.vm.provider "virtualbox" do |vb|
  vb.name = node[:name]
  vb.memory = node[:memory]
  vb.cpus = node[:cpus]
  vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
  vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
end
```

### Current Networking (Line 37)

```ruby
node_config.vm.network "private_network", ip: node[:ip]
```

### Current Node Definitions (Lines 16-20)

```ruby
NODES = [
  { name: "k8s-cp", ip: "192.168.57.10", cpus: 2, memory: 6144, role: "control-plane" },
  { name: "k8s-node-1", ip: "192.168.57.11", cpus: 2, memory: 2048, role: "worker" },
  { name: "k8s-node-2", ip: "192.168.57.12", cpus: 2, memory: 2048, role: "worker" }
]
```

### Important: Two-Layer Migration Strategy

The existing `switch-to-kvm.sh` script handles **Layer 1** (kernel modules):
- ✅ Unloads VirtualBox kernel modules (vboxdrv, vboxnetflt, vboxnetadp)
- ✅ Loads KVM kernel modules (kvm_intel/kvm_amd, kvm)
- ✅ Starts libvirt services (libvirtd, virtlogd, virtlockd)
- ✅ Gets the HOST ready for KVM/QEMU virtualization

**This migration adds Layer 2** (Vagrant provider):
- 📝 Modify Vagrantfile to use libvirt provider
- 📝 Install vagrant-libvirt plugin
- 📝 Update documentation and scripts
- 📝 Get VAGRANT ready to use KVM/QEMU

**Migration Strategy:**
```
Step 1: Run switch-to-kvm.sh         (Layer 1: Kernel modules) ✅ Already have this!
Step 2: Follow this migration plan   (Layer 2: Vagrant config) 📝 This document
```

---

## Chain of Thought Analysis

### Question 1: What needs to change in the Vagrantfile?

**Thought Process:**
1. **Provider block** (lines 40-46) - Most obvious change
   - VirtualBox uses `vb` variable and VirtualBox-specific settings
   - libvirt uses `libvirt` variable and different settings
   - DNS customizations (natdnshostresolver1, natdnsproxy1) are VirtualBox-specific

2. **Do DNS settings map to libvirt?**
   - These are VirtualBox-specific workarounds for DNS resolution
   - libvirt handles DNS differently through its network configuration
   - Answer: **Not needed in libvirt** - it has better DNS handling by default

3. **Resource allocation** (cpus, memory)
   - VirtualBox: `vb.cpus` and `vb.memory`
   - libvirt: `libvirt.cpus` and `libvirt.memory`
   - Answer: **Simple property rename**, semantics identical

4. **VM naming**
   - VirtualBox: `vb.name`
   - libvirt: Uses hostname by default, but can set `libvirt.default_prefix`
   - Answer: **Optional in libvirt**, defaults work fine

**Conclusion:** Provider block needs complete replacement, not modification.

### Question 2: What about networking?

**Thought Process:**
1. **Current setup**: `private_network` with static IP (line 37)
   - This is Vagrant's standard networking syntax
   - Both providers support this syntax ✅

2. **Will the IPs work?**
   - VirtualBox defaults to 192.168.56.0/24 range
   - Current config uses 192.168.57.0/24 range
   - libvirt defaults to 192.168.121.0/24 range
   - Our static IPs should override defaults ✅

3. **Any libvirt-specific options needed?**
   - libvirt supports `:libvirt__network_name` for custom networks
   - libvirt supports `:libvirt__dhcp_enabled` (default: true)
   - libvirt creates a management network automatically
   - Answer: **Basic syntax works**, optional enhancements available

4. **DNS and /etc/hosts**
   - Ansible playbook (common.yml lines 61-69) handles /etc/hosts
   - This is guest-side configuration, provider-independent ✅
   - Answer: **No changes needed**

**Conclusion:** Networking line can stay mostly unchanged, with optional libvirt-specific tuning.

### Question 3: Will the base box work?

**Thought Process:**
1. **Current box**: `bento/ubuntu-24.04` (line 23)

2. **Box compatibility check needed:**
   - Need to verify if bento/ubuntu-24.04 has a libvirt version
   - VirtualBox boxes use `.vmdk`/`.vdi` disk format
   - libvirt boxes use `.qcow2` disk format
   - These are NOT interchangeable

3. **Check Vagrant Cloud:**
   - Most bento boxes support multiple providers
   - Need to verify: https://app.vagrantup.com/bento/boxes/ubuntu-24.04
   - Likely has both virtualbox and libvirt versions

4. **Worst case scenario:**
   - If no libvirt version exists, need alternative box
   - Generic/ubuntu2404 or similar

**Conclusion:** MUST verify box compatibility - this is a potential blocker.

### Question 4: What system dependencies change?

**Thought Process:**
1. **Current dependencies** (from setup-host.sh):
   - Vagrant ✅ (same)
   - VirtualBox ❌ (remove)
   - Ansible ✅ (same)

2. **New dependencies needed**:
   - qemu-kvm (KVM/QEMU hypervisor)
   - libvirt-daemon-system (libvirt service)
   - libvirt-dev (development headers for plugin)
   - ebtables (network bridging)
   - libguestfs-tools (guest filesystem tools)
   - vagrant-libvirt plugin (Vagrant plugin)

3. **Group membership**:
   - Current: vboxusers group
   - New: libvirt group (and/or kvm group)
   - Answer: **Different groups**, setup script must change

**Conclusion:** setup-host.sh needs significant rewrite for libvirt dependencies.

### Question 5: Do the Ansible playbooks need changes?

**Thought Process:**
1. **Playbook examination**:
   - common.yml - System configuration (swap, modules, sysctl, /etc/hosts)
   - binaries-only.yml - Installs Kubernetes binaries
   - containerd.yml - Container runtime config
   - control-plane.yml - kubeadm init
   - calico.yml - CNI installation
   - untaint.yml - Control plane scheduling
   - workers.yml - Worker join

2. **Provider dependency check**:
   - All tasks run INSIDE the guest VM
   - No VirtualBox-specific commands found
   - No provider-specific variables used
   - Answer: **Provider agnostic** ✅

3. **Network assumptions**:
   - Hardcoded IPs in common.yml (lines 67-69)
   - These match Vagrantfile node definitions
   - Provider doesn't matter, IPs are IPs
   - Answer: **No changes needed** ✅

**Conclusion:** Ansible playbooks require ZERO changes - they're provider independent.

### Question 6: What about the switch-to-*.sh scripts?

**Thought Process:**
1. **Current purpose**:
   - switch-to-kvm.sh: Unload VirtualBox modules, load KVM modules
   - switch-to-virtualbox.sh: Unload KVM modules, load VirtualBox modules

2. **After migration**:
   - If using libvirt exclusively, KVM modules always needed
   - Scripts become irrelevant if not switching between providers

3. **Options**:
   - Option A: **Deprecate scripts** - No longer needed
   - Option B: **Keep scripts** - If want ability to switch back
   - Option C: **Repurpose** - Make them switch Vagrant provider (more complex)

4. **Recommendation**:
   - Keep VirtualBox installed alongside libvirt
   - Modify scripts to switch `VAGRANT_DEFAULT_PROVIDER` environment variable
   - Keep kernel module switching functionality
   - This allows easy provider switching for testing

**Conclusion:** Scripts should be adapted, not removed.

---

## Technical Deep Dive

### Provider Configuration Comparison

#### VirtualBox (Current)
```ruby
node_config.vm.provider "virtualbox" do |vb|
  vb.name = node[:name]                                      # VM name in VirtualBox
  vb.memory = node[:memory]                                  # RAM in MB
  vb.cpus = node[:cpus]                                      # CPU count
  vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]  # DNS fix for NAT
  vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]         # DNS proxy for NAT
end
```

**VirtualBox-specific notes:**
- `natdnshostresolver1` and `natdnsproxy1` solve DNS issues with NAT networking
- These are VirtualBox-specific workarounds
- Required because VirtualBox NAT implementation has DNS quirks

#### libvirt (Target)
```ruby
node_config.vm.provider "libvirt" do |libvirt|
  libvirt.cpus = node[:cpus]                               # CPU count
  libvirt.memory = node[:memory]                           # RAM in MB
  # Optional: libvirt.default_prefix = "k8s"              # VM name prefix
  # Optional: libvirt.cpu_mode = "host-passthrough"       # Better CPU performance
end
```

**libvirt-specific notes:**
- No DNS workarounds needed - libvirt handles this correctly
- VM names auto-generated from hostname + prefix
- CPU mode "host-passthrough" gives better performance (exposes all host CPU features)
- Management network created automatically (192.168.121.0/24 by default)

### Networking Configuration Comparison

#### Current Configuration (Works with both providers)
```ruby
node_config.vm.network "private_network", ip: node[:ip]
```

**This syntax is provider-agnostic and works with both!**

#### libvirt-Enhanced Configuration (Optional)
```ruby
node_config.vm.network "private_network",
  ip: node[:ip],
  libvirt__network_name: "k8s-cluster",                    # Custom network name
  libvirt__dhcp_enabled: false,                            # Disable DHCP (using static IPs)
  libvirt__forward_mode: "nat"                             # NAT mode for internet access
```

**Benefits of libvirt-specific options:**
- `libvirt__network_name`: Groups VMs into named network
- `libvirt__dhcp_enabled: false`: Since using static IPs, can disable DHCP
- `libvirt__forward_mode`: Explicit NAT configuration

### Resource Allocation Comparison

| Feature | VirtualBox | libvirt | Notes |
|---------|------------|---------|-------|
| CPU Count | `vb.cpus = 2` | `libvirt.cpus = 2` | Identical semantics |
| Memory (MB) | `vb.memory = 2048` | `libvirt.memory = 2048` | Identical semantics |
| CPU Mode | N/A | `libvirt.cpu_mode = "host-passthrough"` | libvirt-only, better perf |
| Nested Virt | `vb.customize ["modifyvm", :id, "--nested-hw-virt", "on"]` | `libvirt.nested = true` | Simpler in libvirt |

### Management Network

**Important libvirt concept**: libvirt automatically creates a management network.

```ruby
# These are defaults, usually don't need to change
libvirt.management_network_name = 'vagrant-libvirt'
libvirt.management_network_address = '192.168.121.0/24'
libvirt.management_network_mode = 'nat'
```

**Why this matters:**
- Every libvirt VM gets TWO network interfaces by default:
  1. Management network (eth0) - For Vagrant communication
  2. Private network (eth1) - Your 192.168.57.x network

- VirtualBox VMs have the same pattern, so this doesn't break anything
- Guest OS sees same network interface count

---

## Migration Impact Assessment

### Files Requiring Changes

#### 1. **Vagrantfile** - CRITICAL CHANGES

**Lines 40-46: Provider Block**

**Current:**
```ruby
node_config.vm.provider "virtualbox" do |vb|
  vb.name = node[:name]
  vb.memory = node[:memory]
  vb.cpus = node[:cpus]
  vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
  vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
end
```

**New (Basic):**
```ruby
node_config.vm.provider "libvirt" do |libvirt|
  libvirt.cpus = node[:cpus]
  libvirt.memory = node[:memory]
end
```

**New (Recommended):**
```ruby
node_config.vm.provider "libvirt" do |libvirt|
  libvirt.cpus = node[:cpus]
  libvirt.memory = node[:memory]
  libvirt.cpu_mode = "host-passthrough"  # Better performance
  libvirt.default_prefix = "k8s_"        # Consistent VM naming
end
```

**Line 37: Network Configuration**

**Current (works as-is):**
```ruby
node_config.vm.network "private_network", ip: node[:ip]
```

**Enhanced (optional):**
```ruby
node_config.vm.network "private_network",
  ip: node[:ip],
  libvirt__network_name: "k8s-cluster",
  libvirt__dhcp_enabled: false,
  libvirt__forward_mode: "nat"
```

**Lines 4-6: Header Comments**

**Current:**
```ruby
# Kubernetes 1.34.1 cluster with containerd and Calico CNI
# 1 control-plane node + 2 worker nodes
# Full automated provisioning enabled
```

**Should update to:**
```ruby
# Kubernetes 1.34.1 cluster with containerd and Calico CNI
# 1 control-plane node + 2 worker nodes
# Using libvirt/KVM provider for Linux
# Full automated provisioning enabled
```

#### 2. **setup-host.sh** - MAJOR REWRITE NEEDED

**Current VirtualBox Section (Lines 104-161):**
- Checks for VirtualBox
- Installs VirtualBox packages
- Adds user to vboxusers group

**New libvirt Section Needed:**

```bash
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}[2/4] Checking KVM/QEMU${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"

# Check if KVM is available
if [ -e /dev/kvm ]; then
    echo -e "  ${GREEN}✓ /dev/kvm exists${NC}"
else
    echo -e "  ${RED}✗ /dev/kvm not found${NC}"
    echo -e "  ${YELLOW}KVM support may not be enabled in BIOS${NC}"
    exit 1
fi

# Install KVM/QEMU packages
if ! command -v virsh &> /dev/null; then
    echo -e "  ${YELLOW}Installing KVM/QEMU and libvirt...${NC}"
    sudo apt-get update
    sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-dev \
        ebtables libguestfs-tools libxslt-dev libxml2-dev zlib1g-dev ruby-dev
    echo -e "  ${GREEN}✓ KVM/QEMU installed${NC}"
else
    echo -e "  ${GREEN}✓ KVM/QEMU already installed${NC}"
fi

# Check libvirt group membership
if groups | grep -q libvirt; then
    echo -e "  ${GREEN}✓ User is in libvirt group${NC}"
else
    echo -e "  ${YELLOW}⚠ Adding user to libvirt group...${NC}"
    sudo usermod -aG libvirt $(whoami)
    echo -e "  ${GREEN}✓ Added to libvirt group${NC}"
    echo -e "  ${RED}⚠ You must LOG OUT and LOG BACK IN${NC}"
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}[3/4] Checking vagrant-libvirt plugin${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"

if vagrant plugin list | grep -q vagrant-libvirt; then
    PLUGIN_VERSION=$(vagrant plugin list | grep vagrant-libvirt | awk '{print $2}')
    echo -e "  Current version: ${CYAN}$PLUGIN_VERSION${NC}"
    echo -e "  ${GREEN}✓ vagrant-libvirt plugin installed${NC}"
else
    echo -e "  ${YELLOW}Installing vagrant-libvirt plugin...${NC}"
    vagrant plugin install vagrant-libvirt

    if vagrant plugin list | grep -q vagrant-libvirt; then
        echo -e "  ${GREEN}✓ vagrant-libvirt plugin installed${NC}"
    else
        echo -e "  ${RED}✗ Plugin installation failed${NC}"
        exit 1
    fi
fi
```

**Also update Ansible section numbering from [3/3] to [4/4]**

#### 3. **README.md** - DOCUMENTATION UPDATES

**Lines 12-13: Overview section**

**Current:**
```markdown
- **Base OS**: Ubuntu 24.04
- **Hypervisor**: VirtualBox (for Linux x86_64/amd64)
```

**New:**
```markdown
- **Base OS**: Ubuntu 24.04
- **Hypervisor**: libvirt/KVM (native Linux virtualization)
```

**Lines 27-34: Prerequisites**

**Current:**
```markdown
- **Linux system** with x86_64/amd64 architecture
- **VirtualBox** 7.0+ (for Linux)
- **Vagrant** 2.4.0 or later
- **Ansible** 2.15.0 or later
```

**New:**
```markdown
- **Linux system** with x86_64/amd64 architecture with KVM support
- **KVM/QEMU** and libvirt
- **Vagrant** 2.4.0 or later with vagrant-libvirt plugin
- **Ansible** 2.15.0 or later
```

**Lines 52-66: Step 2 Section**

**Current talks about switching to VirtualBox - needs complete rewrite:**

```markdown
### Step 2: Verify KVM Support

Linux systems require hardware virtualization support (Intel VT-x or AMD-V) enabled in BIOS:

```bash
# Check if KVM is available
ls -la /dev/kvm

# If /dev/kvm exists, KVM is ready
# If not, enable virtualization in BIOS
```

The setup script already loaded KVM modules and started libvirt services.
```

**Lines 217-237: Troubleshooting Section**

**Replace "VirtualBox Won't Start VMs" section with:**

```markdown
### libvirt/KVM Issues

**Error**: `ls: cannot access '/dev/kvm': No such file or directory`

**Solution**: Enable virtualization in BIOS
1. Reboot and enter BIOS/UEFI settings
2. Enable Intel VT-x or AMD-V
3. Save and reboot

**Error**: `Call to virDomainCreateWithFlags failed: error: Failed to start domain`

**Solution**: Check libvirt service
```bash
sudo systemctl status libvirtd
sudo systemctl restart libvirtd
```
```

**Lines 229-237: Group membership section**

**Current:**
```markdown
### "User not in vboxusers group"

**Solution**: Add yourself and re-login:

```bash
sudo usermod -aG vboxusers $USER
# Log out and log back in
```
```

**New:**
```markdown
### "User not in libvirt group"

**Solution**: Add yourself and re-login:

```bash
sudo usermod -aG libvirt $USER
# Log out and log back in
```
```

**Lines 112-136: Hypervisor switching section**

**Current discusses switching between KVM and VirtualBox**

**Options:**
- Option A: **Remove entirely** if no longer supporting VirtualBox
- Option B: **Keep as historical reference** with note about previous VirtualBox support
- Option C: **Repurpose** for switching between libvirt and VirtualBox (if keeping both)

**Recommended: Option A** - Simplify documentation

#### 4. **CLAUDE.md** - PROJECT INSTRUCTIONS UPDATE

**Lines 16-17:**

**Current:**
```markdown
- **Base Image**: bento/ubuntu-24.04
- **Hypervisor**: VirtualBox (for Linux)
```

**New:**
```markdown
- **Base Image**: bento/ubuntu-24.04 (libvirt provider)
- **Hypervisor**: libvirt/KVM (native Linux virtualization)
```

**Lines 123:**

**Current:**
```markdown
- **VirtualBox provider**: For Linux systems (x86_64/amd64 architecture)
```

**New:**
```markdown
- **libvirt/KVM provider**: Native Linux virtualization (x86_64/amd64 with VT-x/AMD-V)
```

#### 5. **TESTING-GUIDE.md** - TESTING PROCEDURE UPDATES

**Lines 6-40: Phase 1**

**Current:** "Test Hypervisor Switching Script" - Tests switch-to-virtualbox.sh

**Options:**
- Remove Phase 1 entirely if deprecating hypervisor switching
- Replace with "Test KVM Prerequisites" phase

**Recommended replacement:**

```markdown
### Phase 1: Test KVM Prerequisites

**Test 1: Verify KVM Support**
```bash
# Check KVM device exists
ls -la /dev/kvm

# Check KVM modules loaded
lsmod | grep kvm

# Check libvirt service
systemctl status libvirtd

# Check user group membership
groups | grep libvirt
```

**Success Criteria:**
- /dev/kvm exists and is readable
- kvm and kvm_intel/kvm_amd modules loaded
- libvirtd service is active
- User is member of libvirt group
```

**Lines 64-66: VM status check**

**Current:**
```markdown
- VM is running: `vagrant status` shows "running (virtualbox)"
```

**New:**
```markdown
- VM is running: `vagrant status` shows "running (libvirt)"
```

**Similar changes throughout testing guide for all "virtualbox" → "libvirt" status messages**

#### 6. **verify-cluster.sh** - NO CHANGES NEEDED

This script only runs commands inside VMs - provider-agnostic. ✅

#### 7. **switch-to-kvm.sh** and **switch-to-virtualbox.sh**

**Decision: ENHANCE AND KEEP** ✅

**Why keep them:**
- ✅ Scripts are ESSENTIAL for Layer 1 (kernel modules)
- ✅ Already handle all the kernel module switching correctly
- ✅ Part of the migration workflow
- ✅ Useful if keeping both providers available

**Recommended enhancements:**

Add to the END of `switch-to-kvm.sh`:
```bash
echo -e "${BLUE}Next Steps for Vagrant:${NC}"
echo -e "  If using libvirt provider, ensure vagrant-libvirt is installed:"
echo -e "  ${GREEN}vagrant plugin install vagrant-libvirt${NC}"
echo ""
echo -e "  Start VMs with libvirt provider:"
echo -e "  ${GREEN}vagrant up --provider=libvirt${NC}"
echo ""
echo -e "  Or set default provider:"
echo -e "  ${GREEN}export VAGRANT_DEFAULT_PROVIDER=libvirt${NC}"
echo ""
```

Add to the END of `switch-to-virtualbox.sh`:
```bash
echo -e "${BLUE}Next Steps for Vagrant:${NC}"
echo -e "  Start VMs with VirtualBox provider:"
echo -e "  ${GREEN}vagrant up --provider=virtualbox${NC}"
echo ""
echo -e "  Or set default provider:"
echo -e "  ${GREEN}export VAGRANT_DEFAULT_PROVIDER=virtualbox${NC}"
echo ""
```

**Recommendation:** Keep and enhance - they're part of the two-layer strategy!

---

## Step-by-Step Migration Plan

### Phase 1: Preparation and Validation

#### Step 1.1: Verify Box Compatibility
```bash
# Check if bento/ubuntu-24.04 has libvirt version
vagrant box list
curl -s "https://app.vagrantup.com/api/v1/box/bento/ubuntu-24.04" | grep -o '"name":"libvirt"'

# If not available, research alternative:
# - generic/ubuntu2404
# - ubuntu/noble64
```

**Expected outcome:** Confirm bento/ubuntu-24.04 supports libvirt provider

#### Step 1.2: Backup Current State
```bash
# Destroy current VirtualBox VMs (save any important data first)
vagrant destroy -f

# Backup Vagrantfile
cp Vagrantfile Vagrantfile.virtualbox.backup

# Backup documentation
cp README.md README.md.backup
cp CLAUDE.md CLAUDE.md.backup
cp setup-host.sh setup-host.sh.backup
```

**Expected outcome:** Clean state with backups

#### Step 1.3: Document Current Configuration
```bash
# Save current Vagrant state
vagrant status > pre-migration-vagrant-status.txt

# Save current modules
lsmod | grep -E "(kvm|vbox)" > pre-migration-modules.txt

# Save current VirtualBox VMs (should be empty after destroy)
VBoxManage list vms > pre-migration-vbox-vms.txt
```

**Expected outcome:** Reference documentation of current state

### Phase 2: System Dependencies Installation

#### Step 2.0: Use Existing switch-to-kvm.sh Script (Layer 1)

**FIRST: Let the existing script do the heavy lifting!**

```bash
# Ensure all Vagrant VMs are stopped
vagrant halt

# Run the existing script to switch kernel modules
./switch-to-kvm.sh
```

**This script already handles:**
- ✅ Checks for running VirtualBox VMs
- ✅ Unloads VirtualBox kernel modules
- ✅ Loads KVM kernel modules (kvm_intel or kvm_amd)
- ✅ Starts libvirt services
- ✅ Verifies KVM is functional
- ✅ Checks user group membership

**Verification after script runs:**
```bash
# Should see KVM modules loaded
lsmod | grep kvm

# Should see libvirt running
systemctl status libvirtd

# Should NOT see VirtualBox modules
lsmod | grep vbox  # Should return nothing
```

**Expected outcome:** Kernel modules switched, libvirt services running ✅

#### Step 2.1: Install Additional Dependencies for vagrant-libvirt

**The switch-to-kvm.sh script doesn't install these - we need them for the plugin:**

```bash
# Install build dependencies for vagrant-libvirt plugin compilation
sudo apt-get update
sudo apt-get install -y libxslt-dev libxml2-dev zlib1g-dev ruby-dev \
    libguestfs-tools build-essential

# Verify libvirt-dev is installed (should be from system already)
dpkg -l | grep libvirt-dev
```

**Expected outcome:** Build dependencies installed for vagrant-libvirt plugin

#### Step 2.2: Verify User Permissions

**The switch-to-kvm.sh script already checks this, but verify:**

```bash
# Check group membership
groups | grep libvirt

# If NOT in libvirt group (script should have warned):
sudo usermod -aG libvirt $USER

# IMPORTANT: Log out and log back in for group changes to take effect
```

**After re-login, verify:**
```bash
groups | grep libvirt  # Should show libvirt

# Test libvirt access without sudo
virsh list --all  # Should work without sudo
```

**Expected outcome:** User has libvirt permissions

#### Step 2.3: Install vagrant-libvirt Plugin

```bash
# Install the plugin
vagrant plugin install vagrant-libvirt

# Verify installation
vagrant plugin list | grep libvirt

# Check plugin version
vagrant plugin list
```

**Troubleshooting installation issues:**
```bash
# If installation fails, try updating vagrant first
vagrant version

# If still fails, check build dependencies
sudo apt-get install -y build-essential

# Retry installation
vagrant plugin install vagrant-libvirt
```

**Expected outcome:** vagrant-libvirt plugin successfully installed

### Phase 3: Configuration Changes

#### Step 3.1: Modify Vagrantfile

**Change 1: Update header comments (lines 4-6)**
```ruby
# Kubernetes 1.34.1 cluster with containerd and Calico CNI
# 1 control-plane node + 2 worker nodes
# Using libvirt/KVM provider for Linux
# Full automated provisioning enabled
```

**Change 2: Replace provider block (lines 39-46)**

Replace:
```ruby
      # Provider configuration - VirtualBox for Linux
      node_config.vm.provider "virtualbox" do |vb|
        vb.name = node[:name]
        vb.memory = node[:memory]
        vb.cpus = node[:cpus]
        vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
        vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
      end
```

With:
```ruby
      # Provider configuration - libvirt/KVM for Linux
      node_config.vm.provider "libvirt" do |libvirt|
        libvirt.cpus = node[:cpus]
        libvirt.memory = node[:memory]
        libvirt.cpu_mode = "host-passthrough"  # Expose all host CPU features
        libvirt.default_prefix = "k8s_"        # VM name prefix
      end
```

**Change 3: Enhance network configuration (line 37) - OPTIONAL**

Current works fine:
```ruby
      node_config.vm.network "private_network", ip: node[:ip]
```

Enhanced version (optional):
```ruby
      node_config.vm.network "private_network",
        ip: node[:ip],
        libvirt__network_name: "k8s-cluster",
        libvirt__dhcp_enabled: false,
        libvirt__forward_mode: "nat"
```

**Save and verify syntax:**
```bash
# Check Vagrantfile syntax
ruby -c Vagrantfile  # Should output "Syntax OK"

# Show diff from backup
diff Vagrantfile.virtualbox.backup Vagrantfile
```

**Expected outcome:** Vagrantfile configured for libvirt

#### Step 3.2: Update setup-host.sh

This is a larger change. Key modifications:

1. Update minimum version check variables (lines 18-21):
```bash
MIN_VAGRANT_VERSION="2.4.0"
MIN_LIBVIRT_VERSION="10.0.0"  # Changed from MIN_VBOX_VERSION
MIN_ANSIBLE_VERSION="2.15.0"
```

2. Replace VirtualBox section (lines 104-161) with libvirt section (see detailed code in "Files Requiring Changes" section above)

3. Update section numbering from [2/3] to [2/4] for libvirt and [3/3] to [4/4] for Ansible

4. Update next steps text (lines 226-234):
```bash
echo -e "${CYAN}Next steps:${NC}"
echo -e "  1. Ensure you're logged out and back in (for libvirt group)"
echo ""
echo -e "  2. Start the Kubernetes cluster:"
echo -e "     ${GREEN}vagrant up${NC}"
echo -e "     or"
echo -e "     ${GREEN}vagrant up --provider=libvirt${NC}"
echo ""
echo -e "  3. Verify the cluster:"
echo -e "     ${GREEN}./verify-cluster.sh${NC}"
```

**Expected outcome:** setup-host.sh installs libvirt dependencies

#### Step 3.3: Update Documentation Files

**README.md changes:**
- Lines 12-13: Update hypervisor reference
- Lines 27-34: Update prerequisites
- Lines 52-66: Replace VirtualBox switching with KVM verification
- Lines 112-136: Remove hypervisor switching section (or deprecate)
- Lines 217-237: Update troubleshooting

**CLAUDE.md changes:**
- Lines 16-17: Update base image and hypervisor
- Line 123: Update provider description

**TESTING-GUIDE.md changes:**
- Lines 6-40: Replace Phase 1 with KVM prerequisites test
- Lines 64-66: Update status message format
- Throughout: Replace "virtualbox" with "libvirt" in status checks

**Expected outcome:** All documentation reflects libvirt setup

#### Step 3.4: Handle Hypervisor Switching Scripts

**Recommended approach: Add deprecation notice**

Add to top of `switch-to-kvm.sh` and `switch-to-virtualbox.sh`:

```bash
#!/bin/bash

echo "========================================="
echo "⚠️  DEPRECATION NOTICE"
echo "========================================="
echo ""
echo "This script is deprecated as of 2025-10-27."
echo "The project now uses libvirt/KVM exclusively."
echo ""
echo "This script is kept for historical reference only."
echo "It switches kernel modules but does NOT change"
echo "the Vagrant provider configuration."
echo ""
echo "Press Ctrl+C to cancel, or Enter to continue anyway..."
read

# ... rest of script ...
```

**Alternative: Remove scripts entirely**
```bash
# If choosing to remove
git rm switch-to-kvm.sh switch-to-virtualbox.sh
```

**Expected outcome:** Clear deprecation status of scripts

### Phase 4: Download libvirt Box

#### Step 4.1: Download Base Box for libvirt

```bash
# Add the libvirt version of the box
vagrant box add bento/ubuntu-24.04 --provider=libvirt

# Verify download
vagrant box list

# Should show:
# bento/ubuntu-24.04  (libvirt, X.X.X)
# bento/ubuntu-24.04  (virtualbox, X.X.X)  # If old one still there
```

**If bento/ubuntu-24.04 doesn't support libvirt:**
```bash
# Alternative boxes to try:
vagrant box add generic/ubuntu2404 --provider=libvirt
# or
vagrant box add ubuntu/noble64 --provider=libvirt

# Then update Vagrantfile line 23 to use the alternative box
```

**Expected outcome:** libvirt-compatible box downloaded

### Phase 5: Test Migration

#### Step 5.1: Start Control Plane

```bash
# Ensure KVM modules are loaded
lsmod | grep kvm

# Start control plane with explicit provider flag
vagrant up k8s-cp --provider=libvirt

# Or if VAGRANT_DEFAULT_PROVIDER is set:
export VAGRANT_DEFAULT_PROVIDER=libvirt
vagrant up k8s-cp
```

**What to watch for:**
1. Box download/import (if first time)
2. libvirt domain creation
3. VM boot
4. Ansible provisioning stages
5. Kubernetes initialization

**Verify:**
```bash
# Check vagrant status
vagrant status k8s-cp
# Should show: "running (libvirt)"

# Verify with virsh
virsh list
# Should show the VM running

# SSH into VM
vagrant ssh k8s-cp

# Inside VM, check Kubernetes
kubectl get nodes
# Should show k8s-cp (may be NotReady until CNI installed)
```

**Expected outcome:** Control plane boots and Kubernetes initializes

#### Step 5.2: Start Worker Nodes

```bash
# Start both workers
vagrant up k8s-node-1 k8s-node-2 --provider=libvirt

# Or individually
vagrant up k8s-node-1 --provider=libvirt
vagrant up k8s-node-2 --provider=libvirt
```

**Verify:**
```bash
# Check status
vagrant status

# Should show all three running (libvirt)
# k8s-cp        running (libvirt)
# k8s-node-1    running (libvirt)
# k8s-node-2    running (libvirt)

# Verify with virsh
virsh list
# Should show all three VMs

# Check cluster status
vagrant ssh k8s-cp -c "kubectl get nodes"
# All nodes should show Ready
```

**Expected outcome:** Full cluster running on libvirt

#### Step 5.3: Run Cluster Verification

```bash
# Run verification script
./verify-cluster.sh

# Manual checks
vagrant ssh k8s-cp -c "kubectl get nodes -o wide"
vagrant ssh k8s-cp -c "kubectl get pods -A"

# Deploy test workload
vagrant ssh k8s-cp -c "kubectl create deployment nginx --image=nginx --replicas=3"
vagrant ssh k8s-cp -c "kubectl get pods -o wide"
```

**Success criteria:**
- All nodes show STATUS: Ready
- All system pods Running
- Test deployment distributes across nodes
- Networking works between pods

**Expected outcome:** Cluster fully functional on libvirt

### Phase 6: Performance Validation

#### Step 6.1: Performance Comparison

```bash
# Test network performance between nodes
vagrant ssh k8s-cp -c "ping -c 10 192.168.57.11"

# Test pod network performance
vagrant ssh k8s-cp -c "kubectl run -it --rm --image=nicolaka/netshoot netshoot -- ping 10.244.X.X"

# Check VM resource usage
virsh domstats k8s_k8s-cp

# Compare to VirtualBox (if documented previously)
```

**Expected outcome:** Comparable or better performance than VirtualBox

#### Step 6.2: Stability Test

```bash
# Restart VMs
vagrant reload

# Verify cluster comes back up
vagrant ssh k8s-cp -c "kubectl get nodes"

# Halt and resume
vagrant halt
vagrant up

# Verify persistence
vagrant ssh k8s-cp -c "kubectl get deployments"
# nginx deployment should still exist
```

**Expected outcome:** Cluster survives restarts

### Phase 7: Cleanup

#### Step 7.1: Remove VirtualBox Artifacts (Optional)

```bash
# Remove old VirtualBox boxes
vagrant box remove bento/ubuntu-24.04 --provider=virtualbox

# Uninstall VirtualBox if no longer needed
sudo apt-get remove --purge virtualbox virtualbox-dkms virtualbox-ext-pack

# Remove vboxusers group membership (optional)
sudo gpasswd -d $USER vboxusers
```

**Expected outcome:** Clean system with only libvirt

#### Step 7.2: Document Migration

```bash
# Create migration log
cat > MIGRATION-LOG.md << 'EOF'
# Migration to libvirt Completed

**Date:** $(date)
**Migrated by:** $(whoami)
**Status:** SUCCESS

## What Changed
- Provider: VirtualBox → libvirt/KVM
- Plugin: None → vagrant-libvirt
- Dependencies: VirtualBox → libvirt-daemon-system, qemu-kvm

## Verification
- All nodes: Running on libvirt ✅
- Cluster: Fully functional ✅
- Performance: Stable ✅

## Backup Locations
- Vagrantfile.virtualbox.backup
- README.md.backup
- CLAUDE.md.backup
- setup-host.sh.backup
EOF

# Commit changes to git
git add -A
git commit -m "Migrate from VirtualBox to libvirt/KVM provider

- Updated Vagrantfile to use libvirt provider
- Modified setup-host.sh for libvirt dependencies
- Updated all documentation (README, CLAUDE, TESTING-GUIDE)
- Deprecated hypervisor switching scripts
- Verified cluster functionality on libvirt

Closes #<issue-number>"
```

**Expected outcome:** Migration documented and committed

---

## Nuances and Gotchas

### 1. Box Compatibility - CRITICAL ⚠️

**Problem:** VirtualBox and libvirt boxes use different disk formats and are NOT interchangeable.

**Details:**
- VirtualBox boxes: `.vmdk` or `.vdi` disk images
- libvirt boxes: `.qcow2` disk images
- You CANNOT use a VirtualBox box with libvirt provider

**Solution:**
- Always verify box has libvirt version: `vagrant box add BOX_NAME --provider=libvirt`
- Check Vagrant Cloud before migrating: https://app.vagrantup.com/
- bento boxes usually support both providers
- If no libvirt version exists, find alternative box

**Verification:**
```bash
# Check which providers a box supports
curl -s "https://app.vagrantup.com/api/v1/box/bento/ubuntu-24.04" | jq '.versions[].providers[].name'
```

### 2. Network Interface Ordering

**Problem:** libvirt VMs may have different network interface naming than VirtualBox.

**Details:**
- Both create management interface (eth0)
- Both create private network interface (eth1)
- Interface names might differ (eth0/eth1 vs ens3/ens4 vs enp1s0/enp1s1)
- Depends on Linux predictable network names

**Impact on this project:**
- Ansible playbooks use IP addresses, not interface names ✅
- Kubernetes uses IPs from /etc/hosts ✅
- Should have NO impact ✅

**Verification:**
```bash
# Check interface names inside VM
vagrant ssh k8s-cp -c "ip addr show"

# Verify IP assignment
vagrant ssh k8s-cp -c "ip addr show | grep 192.168.57.10"
```

### 3. Nested Virtualization

**Problem:** If running Vagrant inside a VM (VM inception), KVM requires nested virtualization enabled.

**Details:**
- VirtualBox has simpler nested virtualization
- KVM requires explicit host configuration
- Not applicable if running on bare metal

**Check if needed:**
```bash
# Am I in a VM?
systemd-detect-virt

# If returns "none" → bare metal, no issue
# If returns "kvm" or "vmware" → nested virt needed
```

**Enable nested KVM (if needed):**
```bash
# Intel
echo "options kvm_intel nested=1" | sudo tee /etc/modprobe.d/kvm-intel.conf

# AMD
echo "options kvm_amd nested=1" | sudo tee /etc/modprobe.d/kvm-amd.conf

# Reload module
sudo modprobe -r kvm_intel  # or kvm_amd
sudo modprobe kvm_intel     # or kvm_amd
```

### 4. Storage Pool Location

**Problem:** libvirt stores VM disks in different location than VirtualBox.

**Details:**
- VirtualBox default: `~/VirtualBox VMs/`
- libvirt default: `/var/lib/libvirt/images/`
- Can fill up `/var` partition if small

**Check space:**
```bash
df -h /var/lib/libvirt/images/

# Vagrant box images stored separately:
df -h ~/.vagrant.d/
```

**Change storage pool (if needed):**
```ruby
# In Vagrantfile provider block
libvirt.storage_pool_name = "custom-pool"
```

**Create custom pool:**
```bash
# Define new pool in different location
virsh pool-define-as custom-pool dir --target /home/user/libvirt-storage

# Build and start pool
virsh pool-build custom-pool
virsh pool-start custom-pool
virsh pool-autostart custom-pool
```

### 5. Management Network Conflict

**Problem:** libvirt's default management network (192.168.121.0/24) might conflict with existing network.

**Symptoms:**
- Vagrant up fails with network errors
- Cannot reach VM
- Network already in use errors

**Solution:**
```ruby
# In Vagrantfile, before node definitions
config.vm.provider "libvirt" do |libvirt|
  libvirt.management_network_address = "192.168.122.0/24"  # Different subnet
end
```

**Check for conflicts:**
```bash
# List libvirt networks
virsh net-list --all

# Show network details
virsh net-dumpxml vagrant-libvirt

# Check for IP conflicts
ip route | grep 192.168.121
```

### 6. Group Membership Persistence

**Problem:** Adding user to libvirt group doesn't take effect until re-login.

**Symptoms:**
- `virsh` commands fail with "permission denied"
- Vagrant fails to connect to libvirt
- Works with sudo, fails without

**Solution:**
```bash
# Add to group
sudo usermod -aG libvirt $USER

# MUST log out and log back in
# OR start new login shell
su - $USER

# Verify
groups | grep libvirt
```

**Workaround for testing (temporary):**
```bash
# Run vagrant with sudo (NOT RECOMMENDED for production)
sudo vagrant up --provider=libvirt
```

### 7. DNS Resolution Differences

**Problem:** VirtualBox needed DNS workarounds (natdnshostresolver1), libvirt doesn't.

**Details:**
- VirtualBox NAT had DNS issues → required customizations
- libvirt DNS works correctly by default
- Removing these customizations is CORRECT, not an omission

**What we're removing:**
```ruby
vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
```

**Why it's safe:**
- These are VirtualBox-specific workarounds
- libvirt doesn't have the same DNS issues
- If DNS problems occur, they're different and need different solutions

**Verify DNS works:**
```bash
vagrant ssh k8s-cp -c "nslookup google.com"
vagrant ssh k8s-cp -c "ping -c 2 google.com"
```

### 8. CPU Modes and Performance

**Important:** libvirt has different CPU modes affecting performance.

**Options:**
1. **host-passthrough** (Recommended)
   - Exposes all host CPU features to guest
   - Best performance
   - Reduces live migration compatibility (not relevant for dev cluster)

2. **host-model**
   - Similar to host but allows migration
   - Good performance
   - Better compatibility

3. **custom**
   - Specify exact CPU model
   - Most compatible
   - May lose performance features

**Configuration:**
```ruby
libvirt.cpu_mode = "host-passthrough"  # Recommended for dev
```

**Why this matters for Kubernetes:**
- Better performance for containerd
- Better performance for network (virtio)
- Exposes CPU features to containers (if needed)

### 9. Port Forwarding Syntax Differences

**Problem:** If using port forwarding, syntax differs between providers.

**VirtualBox:**
```ruby
config.vm.network "forwarded_port", guest: 80, host: 8080
```

**libvirt:**
```ruby
config.vm.network "forwarded_port", guest: 80, host: 8080, host_ip: "0.0.0.0"
```

**For this project:**
- We're using private_network with direct IPs
- No port forwarding configured
- Not applicable ✅

### 10. VAGRANT_DEFAULT_PROVIDER Environment Variable

**Problem:** Without setting default provider, must specify --provider every time.

**Annoying:**
```bash
vagrant up --provider=libvirt
vagrant reload --provider=libvirt
vagrant destroy --provider=libvirt
```

**Better:**
```bash
# Set in shell profile (~/.bashrc or ~/.zshrc)
export VAGRANT_DEFAULT_PROVIDER=libvirt

# Now just:
vagrant up
vagrant reload
vagrant destroy
```

**Even better - project-specific:**
```bash
# Create .envrc file in project root (if using direnv)
echo "export VAGRANT_DEFAULT_PROVIDER=libvirt" > .envrc
direnv allow
```

---

## Testing and Validation

### Comprehensive Test Checklist

#### Pre-Migration Tests (Baseline)
- [ ] Document current vagrant status
- [ ] Document current VirtualBox VMs
- [ ] Document current kernel modules loaded
- [ ] Test cluster creation with VirtualBox (if possible)
- [ ] Time cluster provisioning duration
- [ ] Test cluster destruction and recreation

#### Post-Migration Tests (Validation)

**System Level:**
- [ ] `/dev/kvm` exists and is accessible
- [ ] KVM modules loaded (`lsmod | grep kvm`)
- [ ] libvirtd service active (`systemctl status libvirtd`)
- [ ] User in libvirt group (`groups | grep libvirt`)
- [ ] vagrant-libvirt plugin installed (`vagrant plugin list`)

**Box Level:**
- [ ] libvirt box available (`vagrant box list`)
- [ ] Box imports successfully
- [ ] Box creates VM without errors

**Vagrant Level:**
- [ ] `vagrant up` succeeds
- [ ] `vagrant status` shows "running (libvirt)"
- [ ] `vagrant ssh` works to all nodes
- [ ] `vagrant reload` works
- [ ] `vagrant halt` and `vagrant up` cycle works
- [ ] `vagrant destroy` cleans up properly

**Cluster Level:**
- [ ] Control plane initializes
- [ ] Workers join cluster
- [ ] All nodes show Ready status
- [ ] Calico/CNI starts successfully
- [ ] All system pods Running
- [ ] Inter-node networking works (ping test)
- [ ] Pod networking works
- [ ] Service networking works
- [ ] DNS works inside pods

**Performance Level:**
- [ ] Cluster boots in reasonable time (compare to VirtualBox)
- [ ] Network performance acceptable
- [ ] Cluster stable over multiple restarts

**Integration Level:**
- [ ] Ansible provisioning runs without errors
- [ ] All playbooks execute successfully
- [ ] Verify cluster script passes
- [ ] Deploy test workload successfully

### Automated Test Script

Create `test-libvirt-migration.sh`:

```bash
#!/bin/bash

set -e

echo "================================================"
echo "Testing libvirt Migration"
echo "================================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

test_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((TESTS_PASSED++))
}

test_fail() {
    echo -e "${RED}✗${NC} $1"
    ((TESTS_FAILED++))
}

echo "1. Testing KVM Support..."
if [ -e /dev/kvm ]; then
    test_pass "/dev/kvm exists"
else
    test_fail "/dev/kvm not found"
fi

echo ""
echo "2. Testing KVM Modules..."
if lsmod | grep -q "^kvm"; then
    test_pass "KVM module loaded"
else
    test_fail "KVM module not loaded"
fi

echo ""
echo "3. Testing libvirt Service..."
if systemctl is-active --quiet libvirtd; then
    test_pass "libvirtd is active"
else
    test_fail "libvirtd is not active"
fi

echo ""
echo "4. Testing User Permissions..."
if groups | grep -q libvirt; then
    test_pass "User in libvirt group"
else
    test_fail "User not in libvirt group"
fi

echo ""
echo "5. Testing vagrant-libvirt Plugin..."
if vagrant plugin list | grep -q vagrant-libvirt; then
    test_pass "vagrant-libvirt plugin installed"
else
    test_fail "vagrant-libvirt plugin not installed"
fi

echo ""
echo "6. Testing libvirt Box..."
if vagrant box list | grep -q "bento/ubuntu-24.04.*libvirt"; then
    test_pass "libvirt box available"
else
    test_fail "libvirt box not found"
fi

echo ""
echo "================================================"
echo "Test Summary"
echo "================================================"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed! Ready to migrate.${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed. Fix issues before migrating.${NC}"
    exit 1
fi
```

**Usage:**
```bash
chmod +x test-libvirt-migration.sh
./test-libvirt-migration.sh
```

---

## Rollback Plan

### If Migration Fails - How to Revert

#### Immediate Rollback (During Migration)

**If disaster occurs during testing:**

```bash
# Destroy any partial libvirt VMs
vagrant destroy -f

# Remove libvirt VMs from virsh if needed
virsh list --all
virsh destroy k8s_k8s-cp  # Force stop if running
virsh undefine k8s_k8s-cp  # Remove definition

# Restore backups
cp Vagrantfile.virtualbox.backup Vagrantfile
cp README.md.backup README.md
cp CLAUDE.md.backup CLAUDE.md
cp setup-host.sh.backup setup-host.sh

# Switch back to VirtualBox modules
./switch-to-virtualbox.sh

# Restart with VirtualBox
vagrant up --provider=virtualbox
```

**Expected outcome:** Back to working VirtualBox setup

#### Clean Rollback (After Complete Migration)

**If issues discovered after migration:**

```bash
# Use git to revert changes
git status  # See what changed
git diff HEAD~1  # Review last commit

# Revert the migration commit
git revert HEAD  # Creates new commit undoing migration
# or
git reset --hard <commit-before-migration>  # Dangerous - loses commits

# Remove libvirt boxes
vagrant box remove bento/ubuntu-24.04 --provider=libvirt

# Uninstall vagrant-libvirt plugin (optional)
vagrant plugin uninstall vagrant-libvirt

# Download VirtualBox box again if removed
vagrant box add bento/ubuntu-24.04 --provider=virtualbox

# Start with VirtualBox
vagrant up --provider=virtualbox
```

**Expected outcome:** Fully reverted to VirtualBox

#### Partial Rollback (Keep Both Providers)

**If want to keep both options:**

```bash
# Don't remove VirtualBox packages
# Don't remove VirtualBox boxes
# Keep both provider blocks in Vagrantfile:

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  # ... node configuration ...

  # VirtualBox provider
  node_config.vm.provider "virtualbox" do |vb|
    vb.name = node[:name]
    vb.memory = node[:memory]
    vb.cpus = node[:cpus]
    vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
    vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
  end

  # libvirt provider
  node_config.vm.provider "libvirt" do |libvirt|
    libvirt.cpus = node[:cpus]
    libvirt.memory = node[:memory]
    libvirt.cpu_mode = "host-passthrough"
    libvirt.default_prefix = "k8s_"
  end
end

# Then choose provider with flag:
vagrant up --provider=virtualbox
# or
vagrant up --provider=libvirt
```

**Expected outcome:** Flexibility to use either provider

---

## Appendix A: Quick Reference

### Command Comparison

| Task | VirtualBox | libvirt |
|------|-----------|---------|
| Start cluster | `vagrant up --provider=virtualbox` | `vagrant up --provider=libvirt` |
| Check VMs | `VBoxManage list vms` | `virsh list --all` |
| VM details | `VBoxManage showvminfo <name>` | `virsh dominfo <name>` |
| Check modules | `lsmod \| grep vbox` | `lsmod \| grep kvm` |
| Service status | `systemctl status vboxdrv` | `systemctl status libvirtd` |
| User group | `groups \| grep vboxusers` | `groups \| grep libvirt` |
| Remove VM | `VBoxManage unregistervm <name> --delete` | `virsh undefine <name>` |

### File Change Summary

| File | Changes | Complexity |
|------|---------|-----------|
| Vagrantfile | Provider block replacement | Medium |
| setup-host.sh | Dependencies rewrite | High |
| README.md | Documentation updates | Low |
| CLAUDE.md | Reference updates | Low |
| TESTING-GUIDE.md | Test procedure updates | Low |
| switch-to-*.sh | Deprecation or removal | Low |
| Ansible playbooks | None needed ✅ | None |

### Network Reference

| Network | VirtualBox | libvirt |
|---------|-----------|---------|
| Management | 10.0.2.0/24 (NAT) | 192.168.121.0/24 (vagrant-libvirt) |
| Private | 192.168.57.0/24 | 192.168.57.0/24 (same) |
| Interface 1 | eth0 (NAT/mgmt) | eth0 (vagrant-libvirt) |
| Interface 2 | eth1 (private) | eth1 (private) |

### Troubleshooting Quick Reference

| Symptom | Likely Cause | Solution |
|---------|--------------|----------|
| "no KVM device" | Virtualization disabled | Enable VT-x/AMD-V in BIOS |
| "permission denied" | Not in libvirt group | Add user to group + re-login |
| "box not found" | No libvirt box | `vagrant box add --provider=libvirt` |
| "plugin not found" | vagrant-libvirt missing | `vagrant plugin install vagrant-libvirt` |
| "network conflict" | Management network collision | Change management_network_address |
| "can't connect" | libvirtd not running | `sudo systemctl start libvirtd` |

---

## Appendix B: Additional Resources

### Official Documentation
- **vagrant-libvirt**: https://vagrant-libvirt.github.io/vagrant-libvirt/
- **libvirt**: https://libvirt.org/
- **KVM**: https://www.linux-kvm.org/
- **QEMU**: https://www.qemu.org/

### Vagrant Cloud
- **Search for libvirt boxes**: https://app.vagrantup.com/boxes/search?provider=libvirt
- **bento boxes**: https://app.vagrantup.com/bento

### Useful Commands

```bash
# virsh command reference
virsh help
virsh list --all          # List all domains
virsh dominfo <name>      # VM details
virsh domstats <name>     # Resource usage
virsh net-list --all      # List networks
virsh pool-list --all     # List storage pools

# Vagrant debugging
VAGRANT_LOG=debug vagrant up

# Check KVM acceleration
kvm-ok

# Monitor libvirt logs
sudo journalctl -u libvirtd -f
```

---

## Quick Start Guide (TL;DR)

**For those who want the fast path:**

```bash
# 1. Switch kernel modules (Layer 1) - Use existing script!
vagrant halt
./switch-to-kvm.sh

# 2. Install build dependencies
sudo apt-get install -y libxslt-dev libxml2-dev zlib1g-dev ruby-dev \
    libguestfs-tools build-essential

# 3. Install vagrant-libvirt plugin
vagrant plugin install vagrant-libvirt

# 4. Download libvirt box
vagrant box add bento/ubuntu-24.04 --provider=libvirt

# 5. Modify Vagrantfile - Replace provider block (lines 40-46) with:
node_config.vm.provider "libvirt" do |libvirt|
  libvirt.cpus = node[:cpus]
  libvirt.memory = node[:memory]
  libvirt.cpu_mode = "host-passthrough"
  libvirt.default_prefix = "k8s_"
end

# 6. Test!
vagrant up --provider=libvirt

# 7. Verify
vagrant status  # Should show "running (libvirt)"
vagrant ssh k8s-cp -c "kubectl get nodes"
```

**That's it!** Read the rest of this document for details, troubleshooting, and nuances.

---

## Conclusion

### Migration Complexity: MODERATE

**Summary of Changes:**
- ✅ **Simple**: Ansible playbooks unchanged
- ✅ **Simple**: Network topology unchanged
- ⚠️ **Medium**: Vagrantfile provider block replacement
- ⚠️ **Medium**: Box compatibility verification needed
- ⚠️ **Medium**: System dependencies significantly different
- ⚠️ **Complex**: setup-host.sh major rewrite required

### Confidence Level: HIGH

**Why HIGH confidence:**
1. Well-documented providers (both VirtualBox and libvirt)
2. Clear migration path exists
3. Rollback plan is straightforward
4. No data migration needed
5. Ansible playbooks are provider-agnostic
6. Network configuration translates cleanly

### Estimated Time: 2-4 Hours

**Breakdown:**
- Preparation and research: 30 minutes
- Dependency installation: 30 minutes
- Configuration changes: 45 minutes
- Testing and validation: 1-2 hours
- Documentation: 30 minutes

### Recommended Approach: Incremental

1. **Day 1**: Install dependencies, verify box compatibility
2. **Day 2**: Modify Vagrantfile, test control plane only
3. **Day 3**: Add workers, full cluster test
4. **Day 4**: Update documentation, commit changes

### Final Recommendation: PROCEED WITH MIGRATION

**Reasons:**
- ✅ Native Linux virtualization (better performance)
- ✅ No VirtualBox license concerns
- ✅ Better integration with Linux kernel
- ✅ More flexibility with advanced features
- ✅ Active development and community support
- ✅ Clear migration path with manageable complexity

**Risks:**
- ⚠️ Box compatibility (mitigated: bento supports both)
- ⚠️ Learning curve (mitigated: good documentation)
- ⚠️ Time investment (mitigated: incremental approach)

---

**Document Version:** 1.0
**Last Updated:** 2025-10-27
**Author:** Claude Code
**Status:** Ready for Implementation
