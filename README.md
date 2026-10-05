# Orchestration & résilience d'une application web sur Kubernetes (Docker Desktop)

Ce laboratoire déploie une petite API Python sur un cluster Kubernetes local (**Docker Desktop**) avec plusieurs répliques, un routage interne et externe, un stockage persistant et des sondes de santé. Des pannes sont simulées pour vérifier que les pods défaillants se réparent seuls.

## Problématique

Faire tourner un conteneur isolé ne suffit pas en production : s'il plante, le service est interrompu, son état disparaît et rien ne répartit la charge ni n'ajoute de capacité en cas de pic de trafic.

## Solution apportée

L'[API Flask](app/main.py) expose `GET /` (compteur de visites stocké sur disque), `GET /health` (liveness), `GET /ready` (readiness), ainsi que `GET /crash` et `GET /break` pour simuler des pannes. L'image est construite sur Alpine et s'exécute avec l'utilisateur `10001`.

| Fichier | Rôle |
| --- | --- |
| [app/Dockerfile](app/Dockerfile) | Image de l'API, utilisateur non-root, serveur Gunicorn |
| [k8s/namespace.yaml](k8s/namespace.yaml) | Namespace `resilience-lab` |
| [k8s/pvc.yaml](k8s/pvc.yaml) | PersistentVolumeClaim de 100 Mi monté dans `/data` |
| [k8s/deployment.yaml](k8s/deployment.yaml) | 3 répliques, sondes Liveness et Readiness, limites de ressources, contexte de sécurité |
| [k8s/service.yaml](k8s/service.yaml) | Service `ClusterIP` (interne) et Service `NodePort` 30080 (externe) |
| [k8s/ingress.yaml](k8s/ingress.yaml) | Ingress NGINX exposant l'API sur `/` |
| [scripts/deploy.sh](scripts/deploy.sh) | Déploiement complet en une commande |
| [scripts/resilience-test.sh](scripts/resilience-test.sh) | Simulation de pannes et rapport dans `reports/resilience.txt` |
| [scripts/cleanup.sh](scripts/cleanup.sh) | Suppression des ressources déployées |

Fonctionnement des sondes :

- **Readiness** (`/ready`) : un pod dont le volume n'est pas inscriptible est retiré du Service, il ne reçoit plus de trafic.
- **Liveness** (`/health`) : après 3 échecs consécutifs, Kubernetes redémarre le conteneur.
- Si le processus s'arrête (`/crash`), le kubelet relance le conteneur ; si le pod est supprimé, le ReplicaSet en recrée un.

Le PVC est en `ReadWriteOnce` : sur un cluster kind à un seul nœud, les trois répliques peuvent le partager. Sur un cluster multi-nœuds, il faudrait un stockage `ReadWriteMany` ou un StatefulSet.

## Résultats attendus

- Une application accessible via l'Ingress (`http://localhost`) et le NodePort (`http://localhost:30080` via `kubectl port-forward`).
- Un pod en panne redémarré automatiquement, sans interruption visible grâce aux autres répliques.
- Un compteur de visites conservé après les redémarrages de pods.
- Un journal `reports/resilience.txt` et des captures d'écran de la démonstration.

## Démonstration de résilience

Le journal est généré par `scripts/resilience-test.sh` et trois tests y sont exécutés : crash du processus, échec de la liveness probe, suppression d'un pod. Les captures d'écran seront ajoutées dans [docs/screenshots/](docs/screenshots/) après l'exécution sur votre machine :

| Test | Capture |
| --- | --- |
| Pods `Running` après le déploiement | `docs/screenshots/01-pods-running.png` |
| Redémarrage automatique après `/crash` (colonne `RESTARTS`) | `docs/screenshots/02-crash-restart.png` |
| Événements `Unhealthy` puis `Killing` après `/break` | `docs/screenshots/03-liveness-restart.png` |

Ce dépôt n'inclut pas encore de résultats mesurés : le cluster n'a pas été lancé lors de la rédaction des manifestes.

## Lancer le projet

Installer **Docker Desktop** avec **Kubernetes activé** (Settings > Kubernetes, méthode kind) et [kubectl](https://kubernetes.io/docs/tasks/tools/). Les commandes s'exécutent depuis la racine du projet dans **Bash** ; sous Windows, utiliser Git Bash.

**1. Vérifier les outils**

```bash
docker info --format '{{.OSType}}'
kubectl version --client
```

Docker doit afficher `linux`.

**2. Déployer**

```bash
bash scripts/deploy.sh
```

Le script construit l'image, installe l'Ingress NGINX puis applique les manifestes.

**3. Tester l'application**

```bash
curl http://localhost/
# NodePort : port-forward (laisser tourner), puis dans un autre terminal curl http://localhost:30080/health
kubectl -n resilience-lab port-forward svc/api-nodeport 30080:80
kubectl -n resilience-lab get pods
```

Chaque appel à `/` affiche le nom du pod qui répond et le nombre total de visites.

**4. Simuler des pannes**

```bash
bash scripts/resilience-test.sh
kubectl -n resilience-lab get pods --watch
```

Lancer `--watch` dans un second terminal pour observer les redémarrages en direct.

**5. Nettoyer**

```bash
bash scripts/cleanup.sh
```

## Licence

La licence prévue est **MIT**. Le fichier `LICENSE` reste à ajouter.
