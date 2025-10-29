#!/bin/bash
set -e

echo "Fixing firecracker runtime configuration in containerd..."

# The issue is that "aws.firecracker" is not a recognized runtime type
# We need to change it to properly invoke the shim binary

# Backup current config
sudo cp /etc/containerd/config.toml /etc/containerd/config.toml.backup-$(date +%Y%m%d-%H%M%S)

# Replace the firecracker runtime configuration
# Change runtime_type from "aws.firecracker" to empty and set runtime_engine to point to shim
sudo sed -i '/\[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.firecracker\]/,/\[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc\]/ {
  s|runtime_type = "aws.firecracker"|runtime_type = "io.containerd.runtime.v1.linux"|
  s|runtime_engine = ""|runtime_engine = "/usr/local/bin/containerd-shim-aws-firecracker"|
  s|runtime_root = ""|runtime_root = "/var/lib/firecracker-containerd/runtime"|
}' /etc/containerd/config.toml

echo "Configuration updated. Restarting containerd..."
sudo systemctl restart containerd
sleep 5

if sudo systemctl is-active --quiet containerd; then
  echo "Containerd restarted successfully"
  echo ""
  echo "Updated firecracker runtime configuration:"
  grep -A 6 "runtimes.firecracker" /etc/containerd/config.toml
else
  echo "ERROR: Containerd failed to start"
  exit 1
fi
