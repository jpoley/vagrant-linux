# -*- mode: ruby -*-
# vi: set ft=ruby :

# Kubernetes 1.34.1 cluster with containerd and Calico CNI
# 1 control-plane node + 2 worker nodes
# Full automated provisioning enabled

VAGRANTFILE_API_VERSION = "2"

# Cluster configuration
KUBERNETES_VERSION = "1.34.1"
POD_NETWORK_CIDR = "10.244.0.0/16"
CONTROL_PLANE_IP = "192.168.57.10"

# Node definitions
NODES = [
  { name: "k8s-cp", ip: "192.168.57.10", cpus: 2, memory: 6144, role: "control-plane" },
  { name: "k8s-node-1", ip: "192.168.57.11", cpus: 2, memory: 2048, role: "worker" },
  { name: "k8s-node-2", ip: "192.168.57.12", cpus: 2, memory: 2048, role: "worker" }
]

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  config.vm.box = "bento/ubuntu-24.04"
  config.vm.box_check_update = false

  # Increase boot timeout
  config.vm.boot_timeout = 600

  # SSH configuration
  config.ssh.insert_key = true
  config.ssh.forward_agent = true

  # Iterate over each node
  NODES.each_with_index do |node, index|
    config.vm.define node[:name] do |node_config|
      node_config.vm.hostname = node[:name]
      node_config.vm.network "private_network", ip: node[:ip]

      # Provider configuration - VirtualBox for Linux
      node_config.vm.provider "virtualbox" do |vb|
        vb.name = node[:name]
        vb.memory = node[:memory]
        vb.cpus = node[:cpus]
        vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
        vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
      end

      # Common setup for all nodes (swap, kernel modules, sysctl, /etc/hosts)
      node_config.vm.provision "common", type: "ansible" do |ansible|
        ansible.playbook = "playbooks/common.yml"
      end

      # Install Kubernetes binaries (kubelet, kubeadm, kubectl)
      node_config.vm.provision "binaries", type: "ansible" do |ansible|
        ansible.playbook = "playbooks/binaries-only.yml"
      end

      # Install and configure containerd
      node_config.vm.provision "containerd", type: "ansible" do |ansible|
        ansible.playbook = "playbooks/containerd.yml"
      end

      # Control plane specific provisioning
      if node[:role] == "control-plane"
        node_config.vm.provision "control-plane", type: "ansible" do |ansible|
          ansible.playbook = "playbooks/control-plane.yml"
          ansible.extra_vars = {
            control_plane_endpoint: CONTROL_PLANE_IP,
            pod_network_cidr: POD_NETWORK_CIDR,
            kubernetes_version: KUBERNETES_VERSION
          }
        end

        # Install Calico CNI
        node_config.vm.provision "calico", type: "ansible" do |ansible|
          ansible.playbook = "playbooks/calico.yml"
        end

        # Untaint control plane to allow scheduling
        node_config.vm.provision "untaint", type: "ansible" do |ansible|
          ansible.playbook = "playbooks/untaint.yml"
        end
      end

      # Worker nodes join the cluster
      if node[:role] == "worker"
        node_config.vm.provision "worker", type: "ansible" do |ansible|
          ansible.playbook = "playbooks/workers.yml"
        end
      end
    end
  end
end
