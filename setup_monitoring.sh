#!/bin/bash
set -e

##################################################
############## SETUP MONITORING ##################
##################################################

# Create namespace for monitoring components
echo "Creating monitoring namespace..."
kubectl create namespace monitoring || echo "Namespace 'monitoring' already exists."
kubectl get namespace monitoring

# Create namespace for Grafana
echo "Creating Grafana namespace..."
kubectl create namespace my-grafana || echo "Namespace 'my-grafana' already exists."
kubectl get namespace my-grafana

# Install Prometheus using Helm
echo "Adding Prometheus Community Helm chart repository..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

echo "Installing Prometheus Operator using Helm..."
helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring

# Wait for Prometheus Operator to be ready
echo "Waiting for Prometheus Operator and Prometheus to be ready..."
sleep 180  # Increased wait time for Prometheus components

# Create ConfigMap for Grafana dashboards from the JSON file
echo "Creating ConfigMap for Grafana dashboards..."
kubectl create configmap grafana-dashboards --from-file=grafana_k8s_dashboard.json -n my-grafana || echo "ConfigMap 'grafana-dashboards' already exists."

# Apply Grafana deployment
echo "Applying Grafana deployment..."
kubectl apply -f grafana.yaml

# Wait for Grafana to be ready
echo "Waiting for Grafana to be ready..."
sleep 60

# Display monitoring-related resources
echo "Displaying Persistent Volume Claims in the 'my-grafana' namespace..."
kubectl get pvc --namespace=my-grafana -o wide

echo "Displaying deployments in the 'my-grafana' namespace..."
kubectl get deployments --namespace=my-grafana -o wide

echo "Displaying services in the 'my-grafana' namespace..."
kubectl get svc --namespace=my-grafana -o wide

echo "Displaying all resources in the 'my-grafana' namespace..."
kubectl get all --namespace=my-grafana

# Port forward the Grafana UI to localhost
echo "Port forwarding the Grafana UI to localhost on port 3000..."
kubectl port-forward -n my-grafana service/grafana 3000:3000 &