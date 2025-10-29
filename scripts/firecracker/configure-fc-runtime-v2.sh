#!/bin/bash
set -e

echo "Configuring firecracker runtime using v2 shim API..."

# Restore original config
sudo cp /etc/containerd/config.toml.backup-pre-firecracker /etc/containerd/config.toml

# Find the line number where runc runtime starts
LINE_NUM=$(grep -n '\[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc\]' /etc/containerd/config.toml | head -1 | cut -d: -f1)

# Add firecracker runtime using v2 API with proper shim configuration
sudo sed -i "${LINE_NUM}i\\
        [plugins.\"io.containerd.grpc.v1.cri\".containerd.runtimes.firecracker]\\
          runtime_type = \"io.containerd.runc.v2\"\\
          pod_annotations = []\\
          container_annotations = []\\
          privileged_without_host_devices = false\\
          snapshotter = \"devmapper\"\\
\\
          [plugins.\"io.containerd.grpc.v1.cri\".containerd.runtimes.firecracker.options]\\
            BinaryName = \"/usr/local/bin/containerd-shim-aws-firecracker\"\\
            Root = \"/var/lib/firecracker-containerd/runtime\"\\
            SystemdCgroup = false\\
\\
" /etc/containerd/config.toml

echo "Firecracker runtime configuration:"
grep -A 12 "runtimes.firecracker" /etc/containerd/config.toml

echo ""
echo "Restarting containerd..."
sudo systemctl restart containerd
sleep 5

# Check for CRI errors
if sudo journalctl -u containerd --since "10 seconds ago" | grep -q "failed to load plugin io.containerd.grpc.v1.cri"; then
  echo "✗ ERROR: CRI plugin failed"
  sudo journalctl -u containerd -n 30 --no-pager | grep -A 3 "failed"
  exit 1
fi

if sudo systemctl is-active --quiet containerd; then
  echo "✓ Containerd restarted successfully"
else
  echo "✗ ERROR: Containerd failed to start"
  exit 1
fi
