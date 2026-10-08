#!/usr/bin/env bash
# Simule des pannes et enregistre le résultat dans reports/resilience.txt.
cd "$(dirname "$0")/.."
exec > >(tee reports/resilience.txt) 2>&1

K="kubectl -n resilience-lab"
POD=$($K get pods -l app=api -o jsonpath='{.items[0].metadata.name}')

echo "### Etat initial"; $K get pods

echo; echo "### Test 1 : crash du processus ($POD)"
$K exec "$POD" -- wget -qO- http://127.0.0.1:8080/crash
sleep 10; $K get pods

echo; echo "### Test 2 : liveness en échec ($POD)"
$K exec "$POD" -- wget -qO- http://127.0.0.1:8080/break
sleep 30; $K get pods
$K get events --field-selector involvedObject.name="$POD" | grep -E "Unhealthy|Killing"

echo; echo "### Test 3 : suppression d'un pod"
$K delete pod "$POD"
$K rollout status deployment/api --timeout=120s; $K get pods

echo; echo "### Persistance"
curl -s http://localhost/
