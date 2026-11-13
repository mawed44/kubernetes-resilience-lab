#!/usr/bin/env bash
# Déploiement en une commande : cluster kind + image + Ingress + metrics-server + manifestes.
set -euo pipefail
cd "$(dirname "$0")/.."

CLUSTER=k8s-resilience
IMAGE=resilience-api:1.0
NS=resilience-lab
INGRESS_URL=https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.1/deploy/static/provider/kind/deploy.yaml
METRICS_URL=https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.7.2/components.yaml

for tool in docker kubectl kind; do
  command -v "$tool" >/dev/null || { echo "Outil manquant : $tool" >&2; exit 1; }
done
docker info >/dev/null 2>&1 || { echo "Docker n'est pas démarré." >&2; exit 1; }

echo "==> Cluster kind"
if kind get clusters | grep -qx "$CLUSTER"; then
  echo "Le cluster $CLUSTER existe déjà."
else
  kind create cluster --config kind/kind-config.yaml
fi
kubectl config use-context "kind-$CLUSTER" >/dev/null

echo "==> Image Docker"
docker build -t "$IMAGE" app
kind load docker-image "$IMAGE" --name "$CLUSTER"

echo "==> Contrôleur Ingress NGINX"
kubectl apply -f "$INGRESS_URL"
kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=180s

echo "==> metrics-server (nécessaire à l'autoscaling)"
kubectl apply -f "$METRICS_URL"
kubectl -n kube-system patch deployment metrics-server --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' \
  2>/dev/null || true

echo "==> Manifestes de l'application"
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/
kubectl -n "$NS" rollout status deployment/api --timeout=180s

echo
kubectl -n "$NS" get pods,svc,ingress,pvc,hpa
echo
echo "Application disponible :"
echo "  Ingress  -> http://localhost:8080"
echo "  NodePort -> http://localhost:30080"
