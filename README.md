# DevHub Campus — squelette du TP 2 (ArgoCD)

Mono-repo de départ pour le TP `DevHub Campus`. Vous **ne déployez rien** en clonant ce dépôt — tout est à compléter en suivant le polycopié (`argocd/POLYCOPIE-ARGOCD.pdf`).

## Arbo

```
devhub-campus/
├── cluster/              # config du cluster local (kind)
├── services/
│   ├── annuaire/         # service Node.js
│   ├── planning/         # service Python FastAPI
│   └── notif/            # service Go
├── platform/             # ce que vous donnerez à manger à ArgoCD
│   ├── argocd/           # values Helm pour installer ArgoCD lui-même
│   ├── bootstrap/        # root Application (App of Apps)
│   ├── projects/         # AppProject
│   └── apps/
│       ├── dev/          # Application par service, env stable
│       └── preview/      # ApplicationSet par service, previews par branche
└── .github/workflows/    # CI : build d'image OCI et push GHCR
```

## Pré-requis

| Plateforme | À installer |
|---|---|
| **macOS** | Docker Desktop *ou* OrbStack, `kubectl`, `helm`, `kind`, `argocd` CLI |
| **Windows** | Docker Desktop (backend WSL2 obligatoire), Ubuntu WSL2, puis dans WSL : `kubectl`, `helm`, `kind`, `argocd` |
| **Linux** | Docker, `kubectl`, `helm`, `kind`, `argocd` |

Sur Windows, **toutes les commandes du Makefile s'exécutent dans WSL2**. Le terminal PowerShell n'est utilisé que pour `docker version` et l'édition de `C:\Windows\System32\drivers\etc\hosts`.

## Démarrage rapide

```sh
make tools-check           # vérifie les versions des outils
make cluster-up            # démarre un cluster Kubernetes local (kind)
make argocd-install        # installe ingress-nginx + ArgoCD via Helm
make hosts-print           # affiche les lignes à ajouter dans /etc/hosts
make argocd-password       # affiche le mot de passe admin initial
```

Une fois ArgoCD up, vous accédez à l'UI sur `https://argocd.devhub.local`.
Le reste du TP se fait via Git — la commande `kubectl apply` ne devrait plus jamais sortir de votre terminal après l'étape 5, à l'exception de la *root Application*.

## Conventions

- les fichiers comportant des marqueurs `# TODO` doivent être complétés par vos soins ;
- ne renommez pas la structure du dépôt — la grille d'évaluation s'appuie dessus ;
- chaque commit qui touche à `platform/` doit passer un `helm lint` et un `kubectl apply --dry-run=client` en pre-commit hook (à vous de configurer).

## Référence

Polycopié complet : `argocd/POLYCOPIE-ARGOCD.pdf` à la racine du repo de cours.
