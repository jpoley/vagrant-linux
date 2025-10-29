#!/bin/bash
set -e

echo "Configuring firecracker runtime using aws.firecracker runtime type..."

# Restore original config
sudo cp /etc/containerd/config.toml.backup-pre-firecracker /etc/containerd/config.toml

# Find the line number where runc runtime starts
LINE_NUM=$(grep -n '\[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc\]' /etc/containerd/config.toml | head -1 | cut -d: -f1)

# Add firecracker runtime using aws.firecracker type
sudo sed -i "${LINE_NUM}i\\
        [plugins.\\\"io.containerd.grpc.v1.cri\\\".containerd.runtimes.firecracker]\\
          runtime_type = \\\"aws.firecracker\\\"\\
          runtime_engine = \\\"\\\"\\
          runtime_root = \\\"\\\"\\
          privileged_without_host_devices = false\\
          snapshotter = \\\"devmapper\\\"\\
\\
" /etc/containerd/config.toml

echo ""
echo "Firecracker runtime configuration:"
grep -A 6 "runtimes.firecracker" /etc/containerd/config.toml

echo ""
echo "Restarting containerd..."
sudo systemctl restart containerd
sleep 5

# Check for errors
if sudo journalctl -u containerd --since "10 seconds ago" | grep -q "failed to load plugin io.containerd.grpc.v1.cri"; then
  echo "✗ ERROR: CRI plugin failed to load"
  sudo journalctl -u containerd -n 30 --no-pager | grep -A 3 "failed to load"
  exit 1
fi

if sudo systemctl is-active --quiet containerd; then
  echo "✓ Containerd restarted successfully"
else
  echo "✗ ERROR: Containerd failed to start"
  sudo systemctl status containerd --no-pager
  exit 1
fi
