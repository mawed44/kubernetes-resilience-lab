#!/usr/bin/env bash
# Supprime le cluster kind et toutes les ressources associées.
set -euo pipefail
kind delete cluster --name k8s-resilience
