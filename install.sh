#!/bin/bash

# Exit on any error
set -e

# Check if the script is being run as root
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root. Please re-run it. Script closing down without uninstall!"
  exit
fi

# Install K3s (both server and agent on the same machine)
curl -sfL https://get.k3s.io | sh -

# Wait for the node to be Ready, takes ~30 seconds
sleep 30s
k3s kubectl get node

# Set KUBECONFIG environment variable for current user
echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >> ~/.bashrc
source ~/.bashrc

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash

# Verify Helm Installation
helm version

# Set permissions for /etc/rancher to make it accessible
chmod -R 755 /etc/rancher

# Confirm that kubectl is working for non-root users
kubectl get nodes