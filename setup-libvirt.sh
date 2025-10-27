sudo apt update
sudo apt install -y \
  qemu-kvm libvirt-daemon-system libvirt-clients \
  dnsmasq-base bridge-utils \
  build-essential ruby-dev libvirt-dev \
  libxml2-dev libxslt1-dev zlib1g-dev pkg-config

# start & enable libvirtd
sudo systemctl enable --now libvirtd

# make sure the default network exists
sudo virsh net-define /usr/share/libvirt/networks/default.xml 2>/dev/null || true
sudo virsh net-start default 2>/dev/null || true
sudo virsh net-autostart default 2>/dev/null || true

# put your user in the right groups
sudo usermod -aG libvirt,kvm "$USER"
newgrp libvirt <<'EOF'
# reinstall the plugin inside the new group session
vagrant plugin install vagrant-libvirt
EOF

