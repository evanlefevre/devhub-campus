# planning-service

Service Python FastAPI minimaliste : un endpoint `GET /slots` qui renvoie une liste de créneaux mockés, et `GET /healthz` pour les probes.

## Lancer en local

```sh
cd services/planning
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
LOG_LEVEL=debug uvicorn app.main:app --host 0.0.0.0 --port 8080
```

## Containeriser

Étape 3 du TP. Dockerfile à compléter.

## Variables d'environnement

| Nom | Défaut | Rôle |
|---|---|---|
| `PORT` | `8080` | port HTTP |
| `LOG_LEVEL` | `info` | `debug`, `info`, `warn` |
