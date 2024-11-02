#!/bin/bash

# Exit on any error and enable debug output
set -e

# Add Bitnami Helm repo and update
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Set KUBECONFIG environment variable for current user
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >> ~/.bashrc
source ~/.bashrc

# Verify Kubernetes nodes
kubectl get nodes

# Wait until Kubernetes node is ready
echo "Waiting for nodes to be ready..."
kubectl wait --for=condition=Ready node --all --timeout=300s

# Load environment variables for PostgreSQL password or use default values
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-default_password}
POSTGRES_REPLICATION_PASSWORD=${POSTGRES_REPLICATION_PASSWORD:-default_password}

# Ensure current user has appropriate permissions for Kubernetes
kubectl create clusterrolebinding nonroot-admin-binding --clusterrole=cluster-admin --user=$(whoami) || true

# Ensure monitoring namespace exists
kubectl get namespace database || kubectl create namespace database

# Delete existing PostgreSQL StatefulSet
echo "Deleting PostgreSQL StatefulSet if it exists..."
kubectl delete statefulset my-postgresql --namespace database --ignore-not-found
sleep 10  # Give time for pods to terminate

# Delete existing PVC to ensure new password is used
echo "Deleting existing Persistent Volume Claims for PostgreSQL..."
kubectl delete pvc -l app.kubernetes.io/instance=my-postgresql --ignore-not-found --grace-period=0 --force

# Wait for PVC deletion to complete
echo "Waiting for PVCs to be deleted..."
for i in {1..30}; do
  PVC_COUNT=$(kubectl get pvc -l app.kubernetes.io/instance=my-postgresql --namespace database --no-headers 2>/dev/null | wc -l)
  if [ "$PVC_COUNT" -eq "0" ]; then
    echo "All PVCs deleted."
    break
  fi
  sleep 5
done

# Install PostgreSQL with metrics enabled
helm install my-postgresql bitnami/postgresql \
  --namespace database \
  --set global.storageClass=local-path \
  --set persistence.size=10Gi \
  --set replication.enabled=true \
  --set volumePermissions.enabled=true \
  --set auth.password=$POSTGRES_PASSWORD \
  --set auth.replicationPassword=$POSTGRES_REPLICATION_PASSWORD \
  --set resources.requests.cpu=12m \
  --set resources.requests.memory=16Mi \
  --set resources.limits.cpu=30m \
  --set resources.limits.memory=32Mi \
  --set metrics.enabled=true \
  --set metrics.serviceMonitor.enabled=true \
  --set metrics.serviceMonitor.namespace=monitoring \
  --set metrics.serviceMonitor.interval=10s

# Wait for PostgreSQL pods to be running
echo "Waiting for PostgreSQL pods to be ready..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=postgresql --namespace database --timeout=300s

# Verify PostgreSQL Deployment
kubectl get pods --namespace database

# Get PostgreSQL Password
export POSTGRES_PASSWORD=$POSTGRES_PASSWORD
echo "PostgreSQL password: $POSTGRES_PASSWORD"

# Create Primary Service for write operations
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: postgresql-primary
  namespace: database
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "9187"
spec:
  type: ClusterIP
  ports:
    - port: 5432
      targetPort: 5432
  selector:
    app.kubernetes.io/component: primary
EOF

# Create Replica Service for read operations
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: postgresql-replicas
  namespace: database
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "9187"
spec:
  type: ClusterIP
  ports:
    - port: 5432
      targetPort: 5432
  selector:
    app.kubernetes.io/component: read-replica
EOF

# Metric server to monitor CPU and Memory usage
if [ -f components.yaml ]; then
  kubectl apply -f components.yaml --validate=false
else
  echo "Error: components.yaml not found. Please provide the metrics server manifest."
  exit 1
fi

# Create HPA for PostgreSQL
kubectl autoscale statefulset my-postgresql --namespace database --cpu-percent=10 --min=1 --max=6

# Verify HPA
kubectl get hpa --namespace database

## Set Up NodePort Service for PostgreSQL if LoadBalancer fails
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: postgresql-nodeport
  namespace: database
spec:
  type: NodePort
  ports:
    - port: 5432
      targetPort: 5432
      nodePort: 30007
  selector:
    app.kubernetes.io/name: postgresql
EOF

# Verify NodePort service
kubectl get svc postgresql-nodeport --namespace database

# Increase PostgreSQL pod count to allow load balancing between them
echo "Scaling PostgreSQL StatefulSet to 2 replicas..."
kubectl scale statefulset my-postgresql --replicas=2 --namespace database

# Wait for the new PostgreSQL pods to be ready
echo "Waiting for all PostgreSQL pods to be ready..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=postgresql --namespace database --timeout=600s

# Verify that the new pods are running
kubectl get pods -l app.kubernetes.io/name=postgresql --namespace database

# Monitor HPA
kubectl get hpa -n database my-postgresql --watch