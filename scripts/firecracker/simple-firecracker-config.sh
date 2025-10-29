#!/bin/bash
set -e

echo "Adding simple firecracker runtime configuration..."

# Backup
sudo cp /etc/containerd/config.toml /etc/containerd/config.toml.backup-simple-$(date +%Y%m%d-%H%M%S)

# Find the line number where runc runtime starts
LINE_NUM=$(grep -n '\[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc\]' /etc/containerd/config.toml | head -1 | cut -d: -f1)

# Add simple firecracker runtime configuration
sudo sed -i "${LINE_NUM}i\\
        [plugins.\"io.containerd.grpc.v1.cri\".containerd.runtimes.firecracker]\\
          runtime_type = \"aws.firecracker\"\\
          privileged_without_host_devices = false\\
          snapshotter = \"devmapper\"\\
\\
" /etc/containerd/config.toml

echo ""
echo "Added firecracker runtime:"
grep -A 4 "runtimes.firecracker" /etc/containerd/config.toml

echo ""
echo "Restarting containerd..."
sudo systemctl restart containerd
sleep 5

# Verify CRI plugin loaded successfully
if sudo journalctl -u containerd --since "10 seconds ago" | grep -q "failed to load plugin io.containerd.grpc.v1.cri"; then
  echo "✗ ERROR: CRI plugin failed to load"
  sudo journalctl -u containerd -n 20 --no-pager
  exit 1
fi

if sudo systemctl is-active --quiet containerd; then
  echo "✓ Containerd restarted successfully"
  echo "✓ CRI plugin loaded"
else
  echo "✗ ERROR: Containerd failed to start"
  exit 1
fi
