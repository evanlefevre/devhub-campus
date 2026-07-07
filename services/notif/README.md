# notif-service

Service Go minimaliste. Mocke l'émission d'événements de notification : `GET /events` renvoie les derniers événements en mémoire, et `GET /healthz` répond aux probes.

## Lancer en local

```sh
cd services/notif
go mod tidy
LOG_LEVEL=debug go run ./cmd
```

## Containeriser

Étape 3 du TP. Dockerfile à compléter.

## Variables d'environnement

| Nom | Défaut | Rôle |
|---|---|---|
| `PORT` | `8080` | port HTTP |
| `LOG_LEVEL` | `info` | `debug`, `info`, `warn` |
