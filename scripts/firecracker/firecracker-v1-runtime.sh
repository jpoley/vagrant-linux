#!/bin/bash
set -e

echo "Configuring firecracker runtime using v1 runtime API..."

# Backup
sudo cp /etc/containerd/config.toml /etc/containerd/config.toml.backup-v1-$(date +%Y%m%d-%H%M%S)

# Remove existing firecracker runtime section
sudo sed -i '/\[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.firecracker\]/,/\[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc\]/{/\[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc\]/!d}' /etc/containerd/config.toml

# Find the line number where runc runtime starts
LINE_NUM=$(grep -n '\[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc\]' /etc/containerd/config.toml | head -1 | cut -d: -f1)

# Add firecracker runtime using v1 API with runtime_engine
sudo sed -i "${LINE_NUM}i\\
        [plugins.\"io.containerd.grpc.v1.cri\".containerd.runtimes.firecracker]\\
          runtime_type = \"io.containerd.runtime.v1.linux\"\\
          runtime_engine = \"/usr/local/bin/containerd-shim-aws-firecracker\"\\
          runtime_root = \"/var/lib/firecracker-containerd/runtime\"\\
          privileged_without_host_devices = false\\
          snapshotter = \"devmapper\"\\
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
  echo ""
  echo "Verifying runtime registration..."
  sudo crictl --runtime-endpoint unix:///run/containerd/containerd.sock info | grep -A 5 '"firecracker"' || echo "Warning: Runtime not visible in crictl yet"
else
  echo "✗ ERROR: Containerd failed to start"
  sudo systemctl status containerd --no-pager
  exit 1
fi
