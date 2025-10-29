#!/bin/bash
set -e

echo "Setting up firecracker-containerd as separate daemon..."

# Create firecracker-containerd config directory
sudo mkdir -p /etc/firecracker-containerd
sudo mkdir -p /var/lib/firecracker-containerd/containerd

# Create firecracker-containerd configuration
echo "Creating firecracker-containerd configuration..."
sudo tee /etc/firecracker-containerd/config.toml > /dev/null << 'EOF'
version = 2
root = "/var/lib/firecracker-containerd/containerd"
state = "/run/firecracker-containerd"
disabled_plugins = ["cri"]

[grpc]
  address = "/run/firecracker-containerd/containerd.sock"

[plugins]
  [plugins."io.containerd.snapshotter.v1.devmapper"]
    pool_name = "fc-dev-thinpool"
    root_path = "/var/lib/containerd/devmapper"
    base_image_size = "8GB"

[debug]
  level = "debug"
EOF

# Create firecracker runtime configuration
echo "Creating firecracker runtime configuration..."
sudo tee /etc/firecracker-containerd/firecracker-runtime.json > /dev/null << 'EOF'
{
  "firecracker_binary_path": "/usr/local/bin/firecracker",
  "kernel_image_path": "/var/lib/firecracker-containerd/runtime/vmlinux",
  "kernel_args": "console=ttyS0 noapic reboot=k panic=1 pci=off nomodules ro systemd.unified_cgroup_hierarchy=0 systemd.journald.forward_to_console systemd.unit=firecracker.target init=/sbin/overlay-init",
  "root_drive": "/var/lib/firecracker-containerd/runtime/default-rootfs.img",
  "cpu_template": "C3",
  "log_fifo": "/var/log/firecracker-containerd-vm.log",
  "log_level": "Debug",
  "metrics_fifo": "",
  "default_network_interfaces": [{
    "CNIConfig": {
      "NetworkName": "fcnet",
      "InterfaceName": "veth0"
    }
  }]
}
EOF

# Create systemd service for firecracker-containerd
echo "Creating firecracker-containerd systemd service..."
sudo tee /etc/systemd/system/firecracker-containerd.service > /dev/null << 'EOF'
[Unit]
Description=firecracker-containerd container runtime
Documentation=https://github.com/firecracker-microvm/firecracker-containerd
After=network.target local-fs.target firecracker-devmapper.service
Requires=firecracker-devmapper.service

[Service]
Type=notify
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/local/bin/firecracker-containerd \
  --config /etc/firecracker-containerd/config.toml
Restart=always
RestartSec=5
Delegate=yes
KillMode=process
OOMScoreAdjust=-999
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity

[Install]
WantedBy=multi-user.target
EOF

# Build firecracker-containerd binary if not already present
if [ ! -f /usr/local/bin/firecracker-containerd ]; then
  echo "Building firecracker-containerd daemon binary..."
  cd /tmp/firecracker-build/firecracker-containerd
  make firecracker-containerd
  sudo cp firecracker-containerd /usr/local/bin/
  sudo chmod +x /usr/local/bin/firecracker-containerd
fi

# Reload systemd and enable service
echo "Enabling firecracker-containerd service..."
sudo systemctl daemon-reload
sudo systemctl enable firecracker-containerd.service

# Start firecracker-containerd
echo "Starting firecracker-containerd..."
sudo systemctl start firecracker-containerd.service
sleep 5

# Check status
if sudo systemctl is-active --quiet firecracker-containerd; then
  echo "✓ firecracker-containerd is running"
  sudo systemctl status firecracker-containerd --no-pager | head -20
else
  echo "✗ ERROR: firecracker-containerd failed to start"
  sudo journalctl -u firecracker-containerd -n 50 --no-pager
  exit 1
fi

# Verify socket exists
if [ -S /run/firecracker-containerd/containerd.sock ]; then
  echo "✓ firecracker-containerd socket created"
else
  echo "✗ ERROR: firecracker-containerd socket not found"
  exit 1
fi

echo ""
echo "firecracker-containerd daemon setup complete!"
echo "Socket: /run/firecracker-containerd/containerd.sock"
