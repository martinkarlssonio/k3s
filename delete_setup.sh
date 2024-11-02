kubectl delete all --all -n database
kubectl delete namespace database --ignore-not-found
kubectl delete all --all -n monitoring
kubectl delete namespace monitoring --ignore-not-found