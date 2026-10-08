"""Petite API Flask utilisée pour démontrer la résilience sous Kubernetes."""
import os
import signal
import socket
import time

from flask import Flask, jsonify

app = Flask(__name__)

DATA_DIR = os.environ.get("DATA_DIR", "/data")
HITS_FILE = os.path.join(DATA_DIR, "hits.log")
HOSTNAME = socket.gethostname()
STARTED = time.time()

# Passe à True via GET /break : /health répond alors 500 et la liveness probe redémarre le conteneur.
state = {"healthy": True}


def count_hits():
    try:
        with open(HITS_FILE, encoding="utf-8") as f:
            return sum(1 for _ in f)
    except FileNotFoundError:
        return 0


@app.get("/")
def index():
    # Chaque appel ajoute une ligne dans le volume persistant (PVC) partagé par les répliques.
    with open(HITS_FILE, "a", encoding="utf-8") as f:
        f.write(f"{int(time.time())} {HOSTNAME}\n")
    return jsonify(pod=HOSTNAME, visits=count_hits(), uptime_seconds=int(time.time() - STARTED))


@app.get("/health")
def health():
    """Liveness : le processus répond-il correctement ?"""
    if not state["healthy"]:
        return jsonify(status="broken"), 500
    return jsonify(status="ok")


@app.get("/ready")
def ready():
    """Readiness : le volume de données est-il accessible en écriture ?"""
    if not os.access(DATA_DIR, os.W_OK):
        return jsonify(status="not-ready", reason="volume non inscriptible"), 503
    return jsonify(status="ready")


@app.get("/break")
def break_health():
    state["healthy"] = False
    return jsonify(status="health endpoint cassé", pod=HOSTNAME)


@app.get("/crash")
def crash():
    """Simule un crash brutal du processus (le conteneur s'arrête avec le code 1)."""
    os.kill(os.getppid(), signal.SIGTERM)  # arrête Gunicorn (PID 1) : le conteneur s'arrête
    os._exit(1)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
