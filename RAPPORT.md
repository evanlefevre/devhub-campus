# Rapport — TP 2 GitOps avec ArgoCD : `DevHub Campus`

**Binôme :** Evan Lefevre (`evanlefevre`)
**Dépôt :** https://github.com/evanlefevre/devhub-campus
**Cluster :** kind `devhub` (2 nœuds) — Kubernetes v1.29.2

---

## Étape 0 — Outillage

Toutes les commandes du TP sont exécutées dans **WSL2 Ubuntu** (Windows 11), le moteur Docker étant fourni par Docker Desktop via l'intégration WSL2.

| Outil | Version | Rôle |
|---|---|---|
| Docker (engine) | 29.6.1 | runtime conteneur |
| kubectl | v1.36.2 | CLI Kubernetes |
| kind | v0.32.0 | cluster K8s local |
| helm | v3.21.2 | charts (services, ArgoCD, ingress-nginx) |
| argocd CLI | v3.4.4 | login, sync, RBAC, debug |
| yq | v4.53.3 | édition scriptée des values |
| git | 2.43.0 | source de vérité |
| Chart `argo/argo-cd` | 7.6.12 | installation d'ArgoCD |
| Chart `ingress-nginx` | 4.11.3 | exposition des ingress |

Cluster provisionné par `make cluster-up` (kind, control-plane labellisé `ingress-ready=true`, ports 80/443 publiés sur l'hôte). Accès aux services via le fichier `hosts` Windows (`*.devhub.local` → `127.0.0.1`).

---

## Étape 1 — GitOps en 1 page

### Schéma : *push* vs *pull*

```
   MODÈLE PUSH (TP 1)                        MODÈLE PULL / GitOps (TP 2)

   dev ──commit──▶ Git                        dev ──commit──▶ Git (config)
                    │                                          ▲
                    ▼                                          │ (l'agent LIT en continu)
              CI (GitHub Actions)             CI ──build image──▶ GHCR
                    │                                          │
                    │ a les DROITS cluster       (la CI ne touche PLUS au cluster)
                    ▼                                          │
          kubectl apply ──▶ CLUSTER            ArgoCD (dans le cluster) ──sync──▶ CLUSTER
                                                l'agent TIRE l'état désiré et réconcilie
```

La bascule tient en une phrase : **au lieu d'une CI qui *pousse* dans le cluster, un agent installé *dans* le cluster tire en continu l'état décrit dans Git et fait converger le cluster vers cet état.**

### Tableau comparatif

| Question | *Push* (`kubectl apply` en CI) | *Pull* (ArgoCD) |
|---|---|---|
| Qui a les droits sur le cluster ? | La CI (un runner externe détient un kubeconfig à droits élevés). | Seul l'agent ArgoCD, *interne* au cluster. La CI n'a plus aucun droit cluster. |
| Où est l'historique des changements ? | Éclaté : logs de CI (rétention courte) + `kubectl get events` (1 h). | Dans `git log` des repos `platform/` et services. Permanent, reviewable. |
| Qu'arrive-t-il si un dev modifie le cluster à la main ? | Personne ne le voit ; drift silencieux jusqu'au prochain `apply`. | ArgoCD passe **OutOfSync** immédiatement, et avec `selfHeal` réécrase la modif. |
| Comment ajouter un environnement ? | Copier les overlays, créer le namespace, dupliquer la pipeline. | Ajouter un fichier `Application` (~15 lignes) dans `platform/`. |
| Comment faire un rollback ? | Rejouer la CI sur l'ancien commit (en espérant qu'elle repasse). | `git revert` → ArgoCD re-converge (mesuré : **6 s** ici). |
| Combien de pipelines pour 30 services ? | ~30 pipelines avec droits cluster. | 1 agent + 30 fichiers `Application` (ou 1 `ApplicationSet`). |
| Qui voit *en direct* ce qui tourne ? | Personne sans ouvrir Freelens / `kubectl`. | Tout le monde, dans l'UI ArgoCD, d'un coup d'œil. |

### Prise de position

Pour mes projets perso, je **commencerais en push** : pour un seul service et un seul environnement, une CI qui `kubectl apply` est plus simple à mettre en place et à raisonner (pas d'agent à héberger, pas de repo de config séparé). **Je bascule en pull** dès qu'apparaît l'un de ces besoins : plusieurs environnements, plusieurs équipes, des environnements de preview, ou l'exigence d'auditer/annuler chaque changement. GitOps est un investissement de *workflow* qui devient rentable à l'échelle, pas avant.

---

## Étape 2 — Glossaire ArgoCD

| Terme | Ma définition | Exemple dans mon projet |
|---|---|---|
| **Application** (ressource ArgoCD) | Objet K8s (CRD) qui lie une *source* Git à une *destination* cluster+namespace et pilote leur convergence. Ce n'est PAS l'appli métier. | `annuaire-dev` : source `services/annuaire/chart`@`main`, destination `devhub-dev`. |
| **AppProject** | Cloison de sécurité : liste blanche des repos, destinations et types de ressources autorisés pour un groupe d'Applications. | `devhub` : n'autorise que mon repo, les namespaces `devhub-*`, et la création de `Namespace`. |
| **Source** | Le *quoi déployer* : un repo + une révision + un chemin (+ des values Helm). | `repoURL=.../devhub-campus.git`, `path=services/annuaire/chart`, `valueFiles=[values-dev.yaml]`. |
| **Destination** | Le *où déployer* : un serveur cluster + un namespace. | `https://kubernetes.default.svc` + namespace `devhub-dev`. |
| **Sync** | Action de faire converger le cluster vers l'état Git. Manuel, ou automatique (`automated`), avec option `selfHeal`. | `annuaire-dev` est en auto-sync + selfHeal. |
| **Prune** | À la sync, suppression des ressources présentes dans le cluster mais absentes de Git. | Activé sur les previews (indispensable pour les nettoyer) ; `false` en dev (sûr). |
| **App of Apps** | Une Application *racine* dont la source est un dossier de manifestes `Application` : elle crée et gère les autres Applications. | `root` pointe vers `platform/apps/` et crée les 3 apps dev + les 3 ApplicationSets. |
| **ApplicationSet** | Générateur d'Applications à partir d'un *generator* (liste, git, PR…). Une définition → N Applications. | `annuaire-preview` : 1 Application par PR ouverte issue d'une branche `feature/*`. |
| **Sync wave** | Entier annoté sur une ressource qui ordonne les phases d'application (wave -1 avant wave 0…). | ConfigMap en wave `-1` appliqué avant le Deployment en wave `0`. |
| **Hook** (`PreSync`/`Sync`/`PostSync`) | Ressource exécutée *autour* de la sync (avant/pendant/après), typiquement un Job. Un hook `PreSync` qui échoue bloque la sync. | Job `annuaire-...-migrate` en `PreSync` qui logge `migration ok`. |

> **Piège retenu :** on parle de l'*`Application annuaire-dev`* (la ressource ArgoCD, qui vit dans le namespace `argocd`), à ne pas confondre avec l'*application annuaire* (les pods qui vivent dans `devhub-dev`).

---

## Étape 3 — Conteneurisation

Les **3 services** ont été conteneurisés (le poly n'en demandait qu'un, mais les 3 images sont nécessaires pour que l'App of Apps soit entièrement verte). Contraintes respectées : multi-stage, non-root, pas de secret en ENV/ARG, tag = SHA court du commit (`7ef6719`), `LABEL org.opencontainers.image.source`, `/healthz`, respect de `LOG_LEVEL`.

| Service | Base runtime | Taille | UID non-root | Notes |
|---|---|---|---|---|
| annuaire (Node) | `node:20.18.1-alpine3.20` | **195 Mo** | 1001 | `npm ci` avant copie du code (cache) |
| planning (Python) | `python:3.12.7-alpine` | **96 Mo** | 1001 | venv construit dans le stage `build`, copié tel quel |
| notif (Go) | `gcr.io/distroless/static:nonroot` | **13,6 Mo** | 65532 | binaire statique `CGO_ENABLED=0 -ldflags="-s -w"` |

**Pourquoi un venv (et pas un `pip install` global) ?** Le venv isole les dépendances dans un répertoire unique (`/opt/venv`) que l'on copie tel quel du stage `build` vers le stage `runtime`. Un `pip install` global disperse les fichiers dans le système et embarque tout l'outillage pip/setuptools dans l'image finale, empêchant une copie sélective.

**Décision d'optimisation (planning).** Avec `python:3.12-slim` + `uvicorn[standard]`, l'image faisait **256 Mo**, au-dessus de la limite de 200 Mo. Les extras `[standard]` (uvloop, httptools, watchfiles — un binaire Rust) apportent de la performance inutile pour ce service. En passant à `uvicorn` simple, plus aucune extension C n'est nécessaire (fastapi/pydantic ont des wheels musllinux), ce qui a permis de basculer sur **Alpine** : l'image tombe à **96 Mo** avec une marge confortable.

**Comparaison des runtimes pour notif (Go) :** `scratch` (le plus petit, mais ni certificats CA ni `/etc/passwd`), `distroless:nonroot` (retenu — CA + user non-root fournis, aucun shell = surface d'attaque réduite), `alpine` (+5 Mo, mais un shell pour debug). Le distroless est le bon compromis pour un binaire statique.

Images publiées sur `ghcr.io/evanlefevre/{annuaire,planning,notif}:7ef6719`.

---

## Étape 4 — Chart Helm

Structure standard `Chart.yaml` / `values.yaml` / `templates/` pour chaque service. Points clés :

- **`_helpers.tpl`** : les 4 labels obligatoires (`app.kubernetes.io/name`, `/instance`, `/part-of: devhub-campus`, `/managed-by: Helm`) dans le helper `labels` ; le `selectorLabels` ne contient que `name` + `instance` (le selector d'un Deployment est **immuable** — on n'y met que ce qui ne bougera jamais).
- **`securityContext`** réparti : niveau *Pod* = l'identité (`runAsNonRoot`, `runAsUser`) ; niveau *conteneur* = les privilèges (`readOnlyRootFilesystem`, `allowPrivilegeEscalation: false`, `drop: [ALL]`).
- **Multi-environnement** : `values-dev.yaml` / `values-preview.yaml` ne contiennent que les *différences* (log level, répliques, ressources, ingress).
- **`extraLabels`** : ajouté au helper pour porter `devhub.io/env: preview` sur *toutes* les ressources d'une preview (`kubectl get all -A -l devhub.io/env=preview`).

Validation : `helm lint` → `0 chart(s) failed` sur les 3 ; `helm template … | kubectl apply --dry-run=client` passe.

---

## Étape 5 — Installation d'ArgoCD & première Application

- Installé via le chart officiel `argo/argo-cd` (7.6.12), namespace `argocd`, UI exposée sur `argocd.devhub.local` (TLS terminé au niveau ArgoCD en mode `server.insecure`, ingress en HTTP).
- **Rotation du mot de passe admin** : le mot de passe initial (secret `argocd-initial-admin-secret`) a été récupéré puis remplacé via `argocd account update-password`. Le secret initial est désormais caduc.
- Première `Application` `annuaire-dev` créée manuellement, validée en sync manuel, puis basculée en auto-sync + `selfHeal`.

> 📸 **[CAPTURE À INSÉRER n°1]** — UI ArgoCD, vue détail de l'Application `annuaire-dev` montrant le statut **Synced + Healthy** et l'arbre `Deployment → ReplicaSet → Pods`, `Service`, `Ingress`.

### `selfHeal: true` vs `prune: true`

Ce sont **deux protections orthogonales**, dangereuses dans des cas différents :

- **`selfHeal`** = « le cluster ne doit jamais s'écarter de Git ». *Danger :* écrase toute modification manuelle légitime d'urgence (un `kubectl scale` de mitigation à 3 h du matin sera annulé en quelques secondes). Il faut passer par Git même en incident.
- **`prune`** = « ce qui n'est plus dans Git doit disparaître du cluster ». *Danger :* une erreur de `path` dans la source rend « toutes les ressources absentes de Git » → ArgoCD **supprime tout**. Une faute de frappe peut effacer un service entier.

Choix retenu : `selfHeal: true` partout ; `prune: false` en dev (sûr), `prune: true` uniquement sur les previews (où le nettoyage automatique est le but recherché).

---

## Étape 6 — App of Apps & AppProject

`kubectl apply -f platform/bootstrap/root-app.yaml` (précédé de l'`AppProject`) est **l'unique `kubectl apply` de tout le TP**. La root crée ensuite les 3 Applications dev + les 3 ApplicationSets.

**« Pourquoi App of Apps ≠ `kubectl apply -f apps/dev/` ? »**
Un `kubectl apply -f` est une action *ponctuelle et impérative* : elle applique l'état du dossier à l'instant T, puis n'existe plus. Personne ne surveille ensuite. L'App of Apps est *déclarative et continue* : la root est une ressource vivante qui **réconcilie en permanence** le contenu de `platform/apps/` (ajout d'un fichier `Application` → apparition auto ; suppression → prune ; dérive → OutOfSync). De plus, tout hérite de l'`AppProject devhub` (liste blanche des repos, des destinations `devhub-*`, des ressources cluster) — un simple `kubectl apply` court-circuiterait cette cloison de sécurité.

**AppProject `devhub`** : `sourceRepos` = mon seul repo ; `destinations` = cluster local + namespaces `devhub-*` et `argocd` ; `clusterResourceWhitelist` = uniquement `Namespace` (surface minimale, juste ce qu'il faut pour `CreateNamespace=true`).

État validé : `root` + `annuaire-dev` + `planning-dev` + `notif-dev` = **Synced + Healthy**, les 3 services répondent `200` sur `/healthz` via leur ingress.

> 📸 **[CAPTURE À INSÉRER n°2]** — UI ArgoCD, vue **Applications** (grille) montrant les **4 Applications** : la racine `root` et ses trois enfants `annuaire-dev`, `planning-dev`, `notif-dev`, toutes Synced + Healthy.

---

## Étape 7 — ApplicationSet : previews par branche

**Generator retenu : `pullRequest` (GitHub).** Justification :

1. Le generator `scmProvider` github interroge `GET /orgs/<x>/repos`, qui renvoie **404 pour un compte personnel** (`evanlefevre` n'est pas une organisation) — testé et confirmé dans les logs du contrôleur. Le generator `pullRequest` interroge `/repos/<owner>/<repo>/pulls` et fonctionne pour un compte utilisateur.
2. Une preview adossée à une PR ouverte est le pattern *review app* standard : elle naît à l'ouverture de la PR et se nettoie (`prune`) à sa fermeture.
3. Le squelette du TP était déjà calibré pour ce generator (`{{branch_slug}}`).

Un `ApplicationSet` par service (`goTemplate`, filtre `branchMatch: ^feature/.*`, secret `github-token` dans `argocd`, surcharge de `ingress.host` par PR, `prune: true` obligatoire).

**Démonstration validée de bout en bout :**
- Ouverture de la PR #1 (branche `feature/demo-prof`, `replicaCount: 3` sur annuaire) → en ~1 min, **3 Applications preview** créées, namespace `devhub-preview-feature-demo-prof` généré, annuaire tournant avec **3 répliques** (le changement de la branche) vs 2 en dev, ingress `annuaire-feature-demo-prof.devhub.local` accessible (`200`).
- Fermeture de la PR → les 3 Applications sont **prune** (supprimées).
- Réouverture → recréation à l'identique.

> 📸 **[CAPTURE À INSÉRER n°3a]** — UI ArgoCD montrant l'`ApplicationSet` `annuaire-preview` et, en dessous, les Applications preview générées (`*-preview-feature-demo-prof`).
>
> 📸 **[CAPTURE À INSÉRER n°3b]** — le service preview dans le navigateur : `http://annuaire-feature-demo-prof.devhub.local/healthz` renvoyant `{"ok":true,"service":"annuaire"}` (et/ou l'arbre de la preview montrant **3 pods** annuaire).

Reproduction pour la démo au formateur : ouvrir/réouvrir la PR #1 (ou pousser une nouvelle branche `feature/*` + PR), observer l'apparition dans l'UI, refermer pour le prune.

---

## Étape 8 — Bestiaire ArgoCD (drift, rollback, hooks, waves, prune)

| # | Manipulation | Observation |
|---|---|---|
| 1 | `kubectl scale ... --replicas=5` (hors Git) | **selfHeal** ramène à 2 répliques en ~12 s ; l'app reste Synced/Healthy. Sans selfHeal, elle resterait OutOfSync. |
| 2 | Commit `image.tag: v-nexiste-pas` | Sync **réussit** (Git appliqué) mais le nouveau pod part en **ImagePullBackOff**. App **Synced + Progressing** (→ Degraded après le progressDeadline). Les anciens pods maintiennent le `200`. → *Synced ≠ qui marche.* |
| 3 | `git revert` du commit fautif | ArgoCD détecte le nouveau commit et re-converge en **6 s** (après refresh ; jusqu'à 3 min en polling par défaut). Un rollback = un commit tracé. |
| 4 | Hook `PreSync` (Job de migration) | Le Job passe **Running → Succeeded AVANT** l'application du Deployment ; logs : `migration ok`. Un hook PreSync en échec bloquerait la sync. |
| 5 | Sync waves : ConfigMap (wave -1) avant Deployment (wave 0) | Ordre respecté (ConfigMap appliqué en premier). En **cassant** la référence (Deployment → ConfigMap inexistant), le pod part en **CreateContainerConfigError** : la dépendance de wave inférieure manquante empêche le démarrage. |
| 6 | Prune | ConfigMap retiré du chart : avec **prune:false** il reste orphelin (app OutOfSync) ; avec **prune:true** il est **supprimé** (app Synced). |

> 📸 **[CAPTURES À INSÉRER n°4]** — une capture de l'UI ArgoCD par manipulation, au moment du diagnostic. Au minimum les 3 plus parlantes :
> - **4a** — manip 2 : Application `Synced` mais un pod en **ImagePullBackOff** (statut jaune/Progressing).
> - **4b** — manip 5 : le pod en **CreateContainerConfigError** après la coupure du ConfigMap.
> - **4c** — manip 6 : l'Application **OutOfSync** avec le ConfigMap marqué à *prune* (prune:false), puis Synced après prune:true.

**Méthode de diagnostic retenue :** face à un `OutOfSync + Degraded`, je regarde d'abord l'état des pods (`waiting.reason` : ImagePullBackOff ? CreateContainerConfigError ?), puis les *events* du namespace, puis les logs. Le `diff` d'ArgoCD indique si l'écart vient de Git ou d'une modif hors-Git.

---

## Étape 9 — Sécuriser et observer ArgoCD

### RBAC (validé)

Deux rôles dans `argocd-rbac-cm` (matching en **glob**, pas regex POSIX) + un compte local `developer` :

- `developer` : `get` sur `devhub/*` (voit tout), mais `sync` uniquement sur `devhub/*annuaire*`.
- `platform-admin` : tous les droits sur le projet.

Preuve : connecté en `developer`, `argocd app sync annuaire-dev` est **autorisé**, `argocd app sync planning-dev` est **refusé** (`PermissionDenied: applications, sync, devhub/planning-dev, sub: developer`).

> 📸 **[CAPTURE À INSÉRER n°5]** — le terminal montrant, en tant que `developer` : `argocd app sync annuaire-dev` qui réussit, puis `argocd app sync planning-dev` qui renvoie **`PermissionDenied`**.

### Notifications (validé)

Sous-système `argocd-notifications` activé : trigger `on-sync-failed` → template → webhook (mocké avec webhook.site). En cassant volontairement une sync (hook PreSync en `exit 1`), webhook.site a reçu le POST :

```json
{ "application": "annuaire-dev", "revision": "0ccb5b3...", "phase": "Failed",
  "message": "one or more synchronization tasks completed unsuccessfully" }
```

> 📸 **[CAPTURE À INSÉRER n°6]** — l'interface **webhook.site** montrant la requête **POST reçue** avec ce corps JSON (application, revision, phase=Failed, message).

*Piège rencontré :* le destinataire d'une souscription webhook est le **nom** du webhook (`devhub`), pas `webhook:devhub` — sinon ArgoCD cherche un type de service « webhook » et échoue.

### Observabilité — 3 métriques Prometheus utiles

| Métrique | Type / unité | Ce qu'elle me dit en incident |
|---|---|---|
| `argocd_app_info` | gauge (1 série/app, labels `health_status`, `sync_status`, `autosync_enabled`) | Combien d'Applications sont **OutOfSync / Degraded** en ce moment, et lesquelles. La base d'une alerte « X apps non-Healthy ». |
| `argocd_app_sync_total` | compteur (labels `name`, `phase`) | Le **taux d'échec de sync** par app. Observé en vrai : `phase="Failed" 3` sur annuaire-dev pendant la démo notification. Un pic = un déploiement qui n'arrive pas à passer. |
| `argocd_app_reconcile` | histogramme (secondes) | La **durée de réconciliation**. Si le p95 grimpe, le repo-server ou l'API cluster est saturé → les syncs prennent du retard. |

> 📸 **[CAPTURE À INSÉRER n°7]** *(facultatif)* — le terminal montrant la sortie de `curl localhost:8082/metrics | grep argocd_app_info` (ou `argocd_app_sync_total`), pour prouver que les métriques sont exposées.

---

## Étape 11 — Synthèse

### Rétrospective TP 1 → TP 2 (le même geste, deux paradigmes)

| Opération | Ressenti avec ArgoCD | Verdict |
|---|---|---|
| Déployer un service la 1ʳᵉ fois | Un commit du chart, la root fait le reste. Plus lent à *mettre en place* (chart + Application + projet) mais reproductible. | Plus rassurant. |
| Déployer une nouvelle version | Un commit qui change `image.tag`. Rien d'autre. | Nettement plus simple. |
| Rollback | `git revert`, 6 s de reconvergence, tracé. | Le gain le plus spectaculaire. |
| Ajouter un environnement | Un fichier `Application` de 15 lignes. | Plus simple. |
| Env perso par dev | 1 PR = 1 preview complète, sans droits cluster. | Impossible autrement au TP 1. |
| Voir ce qui tourne | Un coup d'œil sur l'UI. | Plus rassurant. |
| Détecter un `kubectl edit` sauvage | OutOfSync immédiat. | Le gain « gouvernance ». |
| Hotfix d'urgence 3 h du matin | **Contrainte** : interdit de `kubectl edit`, il faut une PR même en incident. | Plus contraignant (voir ci-dessous). |
| Droits d'un nouveau dev | Un compte ArgoCD + un rôle, pas de kubeconfig. | Plus sûr. |

**Deux opérations où ArgoCD est plus contraignant :**
1. **Le hotfix d'urgence.** En push, un `kubectl edit` répare en 10 secondes. En GitOps strict (selfHeal), toute modif manuelle est écrasée : il *faut* passer par une PR même à 3 h du matin. Contrainte **justifiée** : elle garantit que l'état réel reste = Git (sinon on accumule des rustines invisibles), mais elle impose d'avoir un chemin de PR/merge rapide, sinon elle rallonge le temps de résolution d'incident.
2. **La mise en place initiale.** Écrire un chart Helm + une Application + un AppProject est plus lourd qu'un `kubectl apply -f` direct pour un premier déploiement jetable. Contrainte **justifiée à l'échelle seulement** — sur un POC d'un jour, c'est du sur-investissement.

**L'opération qui justifierait à elle seule ArgoCD :** les **previews par branche** (étape 7). Offrir à chaque dev un environnement isolé, complet et auto-nettoyé, *sans lui donner de droits cluster*, est quasi impossible en push et trivial en GitOps. C'est là que le changement de paradigme paie.

### Ce qu'ArgoCD ne sait PAS faire — et ce que j'ajouterais en prod

| Thème | Risque en l'état | Outil complémentaire | Référence |
|---|---|---|---|
| Déploiement progressif | Un `image.tag` fautif part à 100 % du trafic d'un coup (pas de canary). | **Argo Rollouts** (ou Flagger) | argo-rollouts.readthedocs.io |
| Validation des manifests | Rien n'empêche un `:latest`, un pod privilégié ou sans `securityContext` d'être syncé. | **Kyverno** ou OPA Gatekeeper (admission) | kyverno.io |
| Secrets dans Git | Un `Secret` en clair dans Git est lisible par quiconque a accès au repo. | **Sealed Secrets** / External Secrets Operator / SOPS | sealed-secrets / external-secrets.io |
| Signature & provenance | ArgoCD déploie n'importe quelle image, y compris non signée / compromise. | **cosign** + admission policy (Sigstore) | docs.sigstore.dev |
| RBAC multi-équipe | Le RBAC CSV local ne passe pas à l'échelle ; pas de SSO d'entreprise. | **OIDC/SSO** (Dex, Okta…) + `AppProject` par équipe | argo-cd rbac docs |
| Disaster recovery | ArgoCD restaure l'*état désiré*, pas les **données** (PVC, base). | **Velero** + snapshots PVC / dumps SGBD | velero.io |
| Multi-cluster | Un seul cluster ; pas de vision hub-and-spoke. | `ApplicationSet` **cluster generator**, secrets de clusters | argo-cd applicationset docs |

**En résumé** : ArgoCD est un excellent *distributeur d'état désiré*, pas une chaîne de release complète. Si je devenais responsable de `DevHub Campus`, mes 3 premières briques après ArgoCD seraient, dans l'ordre : **(1) External/Sealed Secrets** (le trou de sécurité le plus béant), **(2) Kyverno** (empêcher les déploiements non conformes), **(3) Argo Rollouts** (ne plus basculer 100 % du trafic à l'aveugle).

---

## Annexe — Accès & état de la plateforme

- **UI ArgoCD** : https://argocd.devhub.local — `admin` / mot de passe rotaté (voir remise) ; compte `developer` pour la démo RBAC.
- **Services** : `annuaire|planning|notif.devhub.local` (dev), `<service>-feature-demo-prof.devhub.local` (preview).
- **État** : 7 Applications `Synced + Healthy` (root, 3 dev, 3 preview).
