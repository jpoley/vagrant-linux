#!/bin/bash
set -e

echo "Configuring firecracker runtime using io.containerd.firecracker.v1..."

# Restore original config
sudo cp /etc/containerd/config.toml.backup-pre-firecracker /etc/containerd/config.toml

# Update devmapper configuration
sudo sed -i 's|pool_name = ""|pool_name = "fc-dev-thinpool"|' /etc/containerd/config.toml
sudo sed -i 's|root_path = ""|root_path = "/var/lib/containerd/devmapper"|' /etc/containerd/config.toml
sudo sed -i 's|base_image_size = ""|base_image_size = "8GB"|' /etc/containerd/config.toml

# Find the line number where runc runtime starts
LINE_NUM=$(grep -n '\[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc\]' /etc/containerd/config.toml | head -1 | cut -d: -f1)

# Add firecracker runtime using io.containerd.firecracker.v1
sudo sed -i "${LINE_NUM}i\\
        [plugins.\\\"io.containerd.grpc.v1.cri\\\".containerd.runtimes.firecracker]\\
          runtime_type = \\\"io.containerd.firecracker.v1\\\"\\
          privileged_without_host_devices = false\\
          snapshotter = \\\"devmapper\\\"\\
\\
          [plugins.\\\"io.containerd.grpc.v1.cri\\\".containerd.runtimes.firecracker.options]\\
            BinaryName = \\\"/usr/local/bin/containerd-shim-aws-firecracker\\\"\\
\\
" /etc/containerd/config.toml

echo ""
echo "Firecracker runtime configuration:"
grep -A 8 "runtimes.firecracker" /etc/containerd/config.toml

echo ""
echo "Restarting containerd..."
sudo systemctl restart containerd
sleep 5

if sudo systemctl is-active --quiet containerd; then
  echo "✓ Containerd restarted successfully"
else
  echo "✗ ERROR: Containerd failed to start"
  sudo journalctl -u containerd -n 30 --no-pager
  exit 1
fi
