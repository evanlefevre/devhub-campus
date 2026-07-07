# annuaire-service

Service Node.js minimaliste : un endpoint `GET /students` qui renvoie une liste mockée, et un endpoint `GET /healthz` pour les probes Kubernetes.

## Lancer en local

```sh
cd services/annuaire
npm install
LOG_LEVEL=debug npm start
curl localhost:8080/healthz
curl localhost:8080/students
```

## Containeriser

C'est l'étape 3 du TP. Le `Dockerfile` est un squelette avec des `# TODO` — à vous de le compléter en respectant les contraintes du polycopié.

## Variables d'environnement

| Nom | Défaut | Rôle |
|---|---|---|
| `PORT` | `8080` | port d'écoute HTTP |
| `LOG_LEVEL` | `info` | `debug`, `info`, `warn` |
