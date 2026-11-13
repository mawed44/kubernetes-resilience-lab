#!/usr/bin/env bash
# Simule des pannes et vérifie l'auto-réparation. Le journal est écrit dans reports/resilience.txt.
set -uo pipefail
cd "$(dirname "$0")/.."

NS=resilience-lab
URL=http://localhost:8080
mkdir -p reports
exec > >(tee reports/resilience.txt) 2>&1

pods() { kubectl -n "$NS" get pods -l app=api -o wide; }
first_pod() { kubectl -n "$NS" get pods -l app=api -o jsonpath='{.items[0].metadata.name}'; }
wait_ready() { kubectl -n "$NS" rollout status deployment/api --timeout=120s >/dev/null; }

echo "### État initial"
pods

echo; echo "### Test 1 : crash du processus (GET /crash)"
POD=$(first_pod)
echo "Cible : $POD"
kubectl -n "$NS" exec "$POD" -- wget -qO- http://localhost:8080/crash >/dev/null 2>&1 || true
sleep 5
pods
echo "Compteur de redémarrages de $POD :"
kubectl -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].restartCount}{"\n"}'

echo; echo "### Test 2 : liveness probe en échec (GET /break)"
POD=$(kubectl -n "$NS" get pods -l app=api -o jsonpath='{.items[1].metadata.name}')
echo "Cible : $POD"
kubectl -n "$NS" exec "$POD" -- wget -qO- http://localhost:8080/break >/dev/null 2>&1 || true
echo "Attente de 3 échecs consécutifs (~20 s)..."
sleep 25
pods
kubectl -n "$NS" get events --field-selector involvedObject.name="$POD" --sort-by=.lastTimestamp | tail -n 5

echo; echo "### Test 3 : suppression d'un pod (le ReplicaSet le recrée)"
POD=$(first_pod)
kubectl -n "$NS" delete pod "$POD" --wait=false
wait_ready
pods

echo; echo "### Disponibilité pendant les pannes : 20 requêtes sur $URL"
OK=0
for _ in $(seq 1 20); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' "$URL/")" = 200 ] && OK=$((OK+1))
done
echo "$OK/20 réponses 200"

echo; echo "### Persistance : les visites survivent aux redémarrages"
curl -s "$URL/"; echo
