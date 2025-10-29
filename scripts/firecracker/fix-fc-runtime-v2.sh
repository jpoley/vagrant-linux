#!/bin/bash
set -e

echo "Updating firecracker runtime configuration..."

# Backup
sudo cp /etc/containerd/config.toml /etc/containerd/config.toml.backup-runtime-$(date +%Y%m%d-%H%M%S)

# Remove the old firecracker runtime section
sudo sed -i '/\[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.firecracker\]/,/\[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc\]/{/\[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc\]/!d}' /etc/containerd/config.toml

# Add the new firecracker runtime configuration before runc
LINE_NUM=$(grep -n '\[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc\]' /etc/containerd/config.toml | head -1 | cut -d: -f1)

sudo sed -i "${LINE_NUM}i\\
        [plugins.\"io.containerd.grpc.v1.cri\".containerd.runtimes.firecracker]\\
          runtime_type = \"io.containerd.firecracker.v1\"\\
          runtime_engine = \"/usr/local/bin/containerd-shim-aws-firecracker\"\\
          runtime_root = \"/var/lib/firecracker-containerd/runtime\"\\
          privileged_without_host_devices = false\\
          snapshotter = \"devmapper\"\\
\\
          [plugins.\"io.containerd.grpc.v1.cri\".containerd.runtimes.firecracker.options]\\
            FirecrackerBinaryPath = \"/usr/local/bin/firecracker\"\\
            KernelImagePath = \"/var/lib/firecracker-containerd/runtime/vmlinux\"\\
            KernelArgs = \"console=ttyS0 noapic reboot=k panic=1 pci=off nomodules ro systemd.unified_cgroup_hierarchy=0\"\\
            RootDrive = \"/var/lib/firecracker-containerd/runtime/default-rootfs.img\"\\
            CPUTemplate = \"C3\"\\
            LogLevel = \"Debug\"\\
\\
" /etc/containerd/config.toml

echo "Configuration updated"
echo ""
echo "New firecracker runtime config:"
grep -A 14 "runtimes.firecracker" /etc/containerd/config.toml || true

echo ""
echo "Restarting containerd..."
sudo systemctl restart containerd
sleep 5

if sudo systemctl is-active --quiet containerd; then
  echo "✓ Containerd restarted successfully"
else
  echo "✗ ERROR: Containerd failed to start"
  sudo journalctl -u containerd -n 50 --no-pager
  exit 1
fi
