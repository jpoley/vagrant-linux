#!/bin/bash
set -e

echo "Fixing containerd configuration..."

# Update devmapper configuration
sudo sed -i 's|^[[:space:]]*pool_name = ""$|  pool_name = "fc-dev-thinpool"|' /etc/containerd/config.toml
sudo sed -i 's|^[[:space:]]*root_path = ""$|  root_path = "/var/lib/containerd/devmapper"|' /etc/containerd/config.toml
sudo sed -i 's|^[[:space:]]*base_image_size = ""$|  base_image_size = "8GB"|' /etc/containerd/config.toml

echo "Devmapper configuration updated"

# Add firecracker runtime before the runc runtime section
# Find the line number where runc runtime starts
LINE_NUM=$(grep -n '\[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc\]' /etc/containerd/config.toml | head -1 | cut -d: -f1)

if [ -z "$LINE_NUM" ]; then
  echo "Error: Could not find runc runtime section"
  exit 1
fi

# Check if firecracker runtime already exists
if grep -q 'runtimes.firecracker' /etc/containerd/config.toml; then
  echo "Firecracker runtime already exists"
else
  echo "Adding firecracker runtime configuration..."

  # Insert firecracker runtime before runc
  sudo sed -i "${LINE_NUM}i\\
\\
        [plugins.\"io.containerd.grpc.v1.cri\".containerd.runtimes.firecracker]\\
          runtime_type = \"aws.firecracker\"\\
          runtime_engine = \"\"\\
          runtime_root = \"\"\\
          privileged_without_host_devices = false\\
          snapshotter = \"devmapper\"\\
" /etc/containerd/config.toml

  echo "Firecracker runtime configuration added"
fi

# Verify configuration
echo ""
echo "Verifying devmapper configuration..."
grep -A 5 "devmapper" /etc/containerd/config.toml | head -10

echo ""
echo "Verifying firecracker runtime configuration..."
grep -A 6 "runtimes.firecracker" /etc/containerd/config.toml

echo ""
echo "Configuration fix complete!"
