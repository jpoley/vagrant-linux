#!/bin/bash
set -e

echo "Installing Firecracker and firecracker-containerd on k8s-node-1..."

# Define versions
FIRECRACKER_VERSION="v1.10.1"
FC_CONTAINERD_VERSION="v1.10.0"

# Create temp directory
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"

echo "1. Installing Firecracker binary..."
# Download Firecracker
wget -q "https://github.com/firecracker-microvm/firecracker/releases/download/${FIRECRACKER_VERSION}/firecracker-${FIRECRACKER_VERSION}-x86_64.tgz"
tar -xzf "firecracker-${FIRECRACKER_VERSION}-x86_64.tgz"
sudo install -o root -g root -m 0755 release-${FIRECRACKER_VERSION}-x86_64/firecracker-${FIRECRACKER_VERSION}-x86_64 /usr/local/bin/firecracker

echo "2. Installing firecracker-containerd..."
# Download firecracker-containerd
wget -q "https://github.com/firecracker-microvm/firecracker-containerd/releases/download/${FC_CONTAINERD_VERSION}/firecracker-containerd-${FC_CONTAINERD_VERSION#v}-linux-amd64.tar.gz"
tar -xzf "firecracker-containerd-${FC_CONTAINERD_VERSION#v}-linux-amd64.tar.gz"

# Install binaries
sudo install -o root -g root -m 0755 firecracker-containerd /usr/local/bin/
sudo install -o root -g root -m 0755 containerd-shim-aws-firecracker /usr/local/bin/
sudo install -o root -g root -m 0755 firecracker-ctr /usr/local/bin/

echo "3. Setting up /var/lib/firecracker-containerd directory..."
sudo mkdir -p /var/lib/firecracker-containerd/runtime

echo "4. Verifying installations..."
firecracker --version
firecracker-containerd --version

echo "5. Configuring containerd to add firecracker runtime..."
# Backup original config
sudo cp /etc/containerd/config.toml /etc/containerd/config.toml.backup-$(date +%Y%m%d-%H%M%S)

# Find the line number of the untrusted_workload_runtime section
# We'll insert the firecracker config just before it
LINE_NUM=$(grep -n '\[plugins."io.containerd.grpc.v1.cri".containerd.untrusted_workload_runtime\]' /etc/containerd/config.toml | cut -d: -f1)

if [ -z "$LINE_NUM" ]; then
  echo "Error: Could not find untrusted_workload_runtime section in config.toml"
  exit 1
fi

# Insert the firecracker runtime configuration
sudo sed -i "${LINE_NUM}i\\
\\
        [plugins.\"io.containerd.grpc.v1.cri\".containerd.runtimes.firecracker]\\
          runtime_type = \"io.containerd.runc.v2\"\\
          pod_annotations = []\\
          container_annotations = []\\
          privileged_without_host_devices = false\\
          snapshotter = \"overlayfs\"\\
\\
          [plugins.\"io.containerd.grpc.v1.cri\".containerd.runtimes.firecracker.options]\\
            BinaryName = \"/usr/local/bin/containerd-shim-aws-firecracker\"\\
" /etc/containerd/config.toml

echo "6. Restarting containerd..."
sudo systemctl restart containerd
sudo systemctl status containerd --no-pager

echo "7. Verifying containerd can see firecracker runtime..."
sudo crictl info | grep -A 20 runtimes || echo "Run 'sudo crictl info' to verify runtime configuration"

# Cleanup
cd /
rm -rf "$TMP_DIR"

echo ""
echo "Installation complete! Firecracker runtime is now configured."
echo "You can now deploy pods with runtimeClassName: firecracker"
