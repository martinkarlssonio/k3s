#!/bin/bash -u
echo "############## UNINSTALL STARTED"

# Exit on any error and enable debug mode
set -e
set -x

# Debugging: Print effective user ID and username
echo "EUID: $EUID"
whoami

# Check if the script is being run as root
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root. Please re-run it. Script closing down without uninstall!"
  exit
fi

echo "Proceeding with uninstall.."
sleep 1

# Set KUBECONFIG environment variable for current user
echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >> ~/.bashrc
source ~/.bashrc

# Uninstall k3s (both server and agent)
/usr/local/bin/k3s-uninstall.sh

# Remove Helm installation
if command -v helm &> /dev/null; then
  rm -rf /usr/local/bin/helm
  echo "Helm uninstalled successfully."
else
  echo "Helm is not installed."
fi

# Remove k3s residual directories and files
rm -rf /etc/rancher
rm -rf /var/lib/rancher
rm -rf /var/lib/kubelet
rm -rf /etc/rancher/k3s

# Verify that k3s and Helm are removed
if command -v k3s &> /dev/null; then
  echo "k3s is still installed."
else
  echo "k3s uninstalled successfully."
fi

if command -v helm &> /dev/null; then
  echo "Helm is still installed."
else
  echo "Helm uninstalled successfully."
fi
