#!/usr/bin/env bash
# Déploie l'application sur le cluster Kubernetes de Docker Desktop.
set -euo pipefail
cd "$(dirname "$0")/.."

INGRESS_URL=https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.1/deploy/static/provider/cloud/deploy.yaml

kubectl config use-context docker-desktop

echo "==> Image"
docker build -t resilience-api:1.0 app

echo "==> Ingress NGINX"
kubectl apply -f "$INGRESS_URL"
kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=180s

echo "==> Application"
kubectl apply -f k8s/namespace.yaml
# Le webhook de l'Ingress peut mettre quelques secondes à être prêt : on réessaie une fois.
kubectl apply -f k8s/ || { sleep 20; kubectl apply -f k8s/; }
kubectl -n resilience-lab rollout status deployment/api --timeout=180s

kubectl -n resilience-lab get pods,svc,ingress,pvc
echo "Ingress : http://localhost"
echo "NodePort : kubectl -n resilience-lab port-forward svc/api-nodeport 30080:80  puis  http://localhost:30080"
