# libvirt Migration - Manual Steps Checklist

**Date:** 2025-10-27
**Status:** Ready to Execute

---

## What I've Done For You

✅ **Backed up Vagrantfile** → `Vagrantfile.virtualbox.backup`
✅ **Updated Vagrantfile** to use libvirt provider with optimal settings
✅ **Verified syntax** of the new Vagrantfile

---

## What You Need To Do

Run these commands in order. I've organized them into logical steps:

### Step 1: Switch Kernel Modules (Layer 1)

You mentioned you're about to run this - go ahead and run it now:

```bash
cd /home/jpoley/vagrant-linux && ./switch-to-kvm.sh
```

**What this does:**
- Unloads VirtualBox kernel modules
- Loads KVM kernel modules (kvm_intel or kvm_amd)
- Starts libvirt services
- Verifies KVM is functional

**Expected output:** Should complete successfully with green checkmarks

---

### Step 2: Install Build Dependencies

After the kernel switch completes, install the remaining build dependencies:

```bash
sudo apt-get update
sudo apt-get install -y libxslt-dev libxml2-dev libguestfs-tools
```

**What this does:**
- Installs XML processing libraries (libxslt, libxml2)
- Installs guest filesystem tools (libguestfs-tools)
- These are needed to compile the vagrant-libvirt plugin

**Expected output:** Package installation messages, should complete without errors

---

### Step 3: Verify User Permissions

Check that you're in the libvirt group (the script should have already done this):

```bash
groups | grep libvirt
```

**Expected output:** Should show "libvirt" in your groups

**If NOT in the group, run:**
```bash
sudo usermod -aG libvirt $USER
```

**⚠️ IMPORTANT:** If you just added yourself to the group, you MUST log out and log back in (or reboot) for the group membership to take effect!

To verify it worked after re-login:
```bash
virsh list --all  # Should work without sudo
```

---

### Step 4: Install vagrant-libvirt Plugin

Now install the Vagrant plugin for libvirt:

```bash
vagrant plugin install vagrant-libvirt
```

**What this does:**
- Downloads and compiles the vagrant-libvirt plugin
- This may take a few minutes as it compiles native extensions

**Expected output:** Progress messages, should end with "Installed the plugin 'vagrant-libvirt'"

**Verify installation:**
```bash
vagrant plugin list
```

Should show something like:
```
vagrant-libvirt (0.x.x, global)
```

---

### Step 5: Download libvirt Box

Download the libvirt version of the Ubuntu box:

```bash
vagrant box add bento/ubuntu-24.04 --provider=libvirt
```

**What this does:**
- Downloads the libvirt-compatible version of bento/ubuntu-24.04
- This is a different format than the VirtualBox version (.qcow2 vs .vmdk)
- Download size: ~500MB-1GB

**Expected output:** Progress bar, download and import messages

**Verify:**
```bash
vagrant box list
```

Should show:
```
bento/ubuntu-24.04  (libvirt, <version>)
bento/ubuntu-24.04  (virtualbox, <version>)  # Old one, if still there
```

---

### Step 6: Destroy Old VirtualBox VMs

Before starting with libvirt, clean up any old VirtualBox VMs:

```bash
vagrant destroy -f
```

**What this does:**
- Removes any existing VirtualBox VMs from previous runs
- Required because we're switching providers

**Expected output:** Messages about destroying VMs, or "VM not created" if already clean

---

### Step 7: Test with libvirt! 🚀

Now for the moment of truth - start the cluster with libvirt:

```bash
# Optional: Set default provider to avoid typing --provider every time
export VAGRANT_DEFAULT_PROVIDER=libvirt

# Start the control plane first
vagrant up k8s-cp --provider=libvirt
```

**What this does:**
- Creates a new VM using libvirt/KVM
- Boots Ubuntu 24.04
- Runs all the Ansible provisioning (common, binaries, containerd, control-plane, calico, untaint)
- Initializes Kubernetes

**Expected output:**
- VM creation messages from libvirt
- Ansible playbook execution
- Should complete successfully

**Verify:**
```bash
# Check vagrant status
vagrant status

# Should show: k8s-cp running (libvirt)

# Check with virsh
virsh list

# Should show the VM running

# SSH and check Kubernetes
vagrant ssh k8s-cp -c "kubectl get nodes"
```

---

### Step 8: Start Worker Nodes

If the control plane works, start the workers:

```bash
vagrant up k8s-node-1 k8s-node-2 --provider=libvirt
```

**Verify full cluster:**
```bash
vagrant ssh k8s-cp -c "kubectl get nodes -o wide"
```

All nodes should show STATUS: Ready

---

### Step 9: Run Verification

Run the cluster verification script:

```bash
./verify-cluster.sh
```

**Expected output:** All checks should pass with green checkmarks

---

## Troubleshooting

### If "Permission denied" on /dev/kvm
```bash
ls -la /dev/kvm
# Should show your user has access via libvirt group
# If not, check group membership and re-login
```

### If "Failed to connect to libvirt"
```bash
sudo systemctl status libvirtd
# Should show "active (running)"
# If not:
sudo systemctl start libvirtd
```

### If "Box not found" error
```bash
# Check if box downloaded
vagrant box list | grep libvirt

# If not present, retry download
vagrant box add bento/ubuntu-24.04 --provider=libvirt
```

### If vagrant plugin install fails
```bash
# Check you have all build dependencies
dpkg -l | grep -E "(libxslt-dev|libxml2-dev|ruby-dev|build-essential)"

# If any missing, install them first
sudo apt-get install -y libxslt-dev libxml2-dev libguestfs-tools build-essential ruby-dev

# Retry plugin installation
vagrant plugin install vagrant-libvirt
```

---

## What Changed in the Vagrantfile

**Old VirtualBox Provider:**
```ruby
node_config.vm.provider "virtualbox" do |vb|
  vb.name = node[:name]
  vb.memory = node[:memory]
  vb.cpus = node[:cpus]
  vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
  vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
end
```

**New libvirt Provider:**
```ruby
node_config.vm.provider "libvirt" do |libvirt|
  libvirt.cpus = node[:cpus]
  libvirt.memory = node[:memory]
  libvirt.cpu_mode = "host-passthrough"  # Better performance
  libvirt.default_prefix = "k8s_"        # VM name prefix
end
```

**Key differences:**
- Removed VirtualBox-specific DNS workarounds (not needed in libvirt)
- Added `cpu_mode = "host-passthrough"` for better performance
- Added VM name prefix for easier identification in virsh

---

## Rollback Plan

If anything goes wrong, you can rollback:

```bash
# Destroy libvirt VMs
vagrant destroy -f

# Restore original Vagrantfile
cp Vagrantfile.virtualbox.backup Vagrantfile

# Switch back to VirtualBox modules
./switch-to-virtualbox.sh

# Start with VirtualBox
vagrant up --provider=virtualbox
```

---

## Next Steps After Success

Once everything is working:

1. **Optional:** Remove old VirtualBox boxes to save space:
   ```bash
   vagrant box remove bento/ubuntu-24.04 --provider=virtualbox
   ```

2. **Optional:** Set default provider permanently in your shell profile:
   ```bash
   echo 'export VAGRANT_DEFAULT_PROVIDER=libvirt' >> ~/.bashrc
   source ~/.bashrc
   ```

3. **Optional:** Update other documentation files (README.md, CLAUDE.md, etc.)

---

## Summary

**You're almost there!** The configuration is ready. Just run the commands above in order and you'll be running on libvirt/KVM. The hard work is done - now it's just execution.

**Estimated time:** 20-30 minutes (mostly waiting for downloads and VM boot)

Let me know once you've completed the steps and I can help with verification or troubleshooting!
