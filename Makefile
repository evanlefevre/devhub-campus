SHELL := /bin/bash
CLUSTER ?= devhub
ARGOCD_CHART_VERSION ?= 7.6.12
INGRESS_CHART_VERSION ?= 4.11.3

SERVICES := annuaire planning notif

.PHONY: help tools-check cluster-up cluster-down argocd-install argocd-password hosts-print images kind-load set-image-tags push clean

help:
	@echo "Cibles disponibles :"
	@echo "  tools-check       - vérifie que les outils requis sont installés"
	@echo "  cluster-up        - démarre un cluster Kubernetes local (kind)"
	@echo "  cluster-down      - détruit le cluster"
	@echo "  argocd-install    - installe ingress-nginx + ArgoCD via Helm"
	@echo "  argocd-password   - affiche le mot de passe admin initial"
	@echo "  hosts-print       - affiche les lignes à ajouter dans /etc/hosts"
	@echo "  images            - construit les 3 images de services"
	@echo "  clean             - détruit le cluster et nettoie les artefacts locaux"

tools-check:
	@for t in docker kubectl helm kind argocd; do \
		command -v $$t >/dev/null 2>&1 || { echo "manquant : $$t"; exit 1; }; \
	done
	@echo "tous les outils sont présents."
	@docker version --format '  docker  : {{.Server.Version}}'
	@kubectl version --client --short 2>/dev/null | sed 's/^/  /'
	@helm version --short | sed 's/^/  helm    : /'
	@kind version | sed 's/^/  /'
	@argocd version --client --short 2>/dev/null | sed 's/^/  /'

cluster-up:
	kind create cluster --name $(CLUSTER) --config cluster/kind-config.yaml
	@echo ">>> cluster prêt — contexte courant : kind-$(CLUSTER)"

cluster-down:
	kind delete cluster --name $(CLUSTER)

argocd-install:
	helm repo add argo https://argoproj.github.io/argo-helm
	helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
	helm repo update
	helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
		--namespace ingress-nginx --create-namespace \
		--version $(INGRESS_CHART_VERSION) \
		--set controller.service.type=NodePort \
		--set-string controller.nodeSelector."ingress-ready"=true \
		--set "controller.tolerations[0].key=node-role.kubernetes.io/control-plane" \
		--set "controller.tolerations[0].operator=Exists" \
		--set "controller.tolerations[0].effect=NoSchedule" \
		--set controller.hostPort.enabled=true \
		--set controller.publishService.enabled=false
	kubectl wait --namespace ingress-nginx \
		--for=condition=ready pod \
		--selector=app.kubernetes.io/component=controller \
		--timeout=180s
	helm upgrade --install argocd argo/argo-cd \
		--namespace argocd --create-namespace \
		--version $(ARGOCD_CHART_VERSION) \
		-f platform/argocd/values.yaml

argocd-password:
	@kubectl -n argocd get secret argocd-initial-admin-secret \
		-o jsonpath='{.data.password}' | base64 -d ; echo

hosts-print:
	@echo "ajoutez ces lignes à votre fichier hosts :"
	@echo "  macOS/Linux : /etc/hosts"
	@echo "  Windows     : C:\\Windows\\System32\\drivers\\etc\\hosts"
	@echo ""
	@echo "127.0.0.1  argocd.devhub.local"
	@echo "127.0.0.1  annuaire.devhub.local"
	@echo "127.0.0.1  planning.devhub.local"
	@echo "127.0.0.1  notif.devhub.local"

GHCR_USER ?= evanlefevre
SHA := $(shell git rev-parse --short HEAD 2>/dev/null || echo dev)

# Construit les 3 images, taguées avec le SHA court du commit (jamais `latest`).
images:
	@for svc in $(SERVICES); do \
		echo ">>> build $$svc:$(SHA)"; \
		docker build -t ghcr.io/$(GHCR_USER)/$$svc:$(SHA) services/$$svc; \
	done

# Charge les images dans les nœuds kind. Avec imagePullPolicy: IfNotPresent,
# les pods trouvent l'image en local et ne tentent aucun pull GHCR : le cluster
# de dev est vert sans authentification registry.
kind-load:
	@for svc in $(SERVICES); do \
		echo ">>> kind load $$svc:$(SHA)"; \
		kind load docker-image ghcr.io/$(GHCR_USER)/$$svc:$(SHA) --name $(CLUSTER); \
	done

# Écrit le SHA courant comme image.tag dans les values dev + preview des 3
# services. Le tag vit ainsi dans Git (source de vérité GitOps) — un nouveau
# build = un commit qui change le tag, exactement le flux visé par le TP.
set-image-tags:
	@for svc in $(SERVICES); do \
		for f in values-dev values-preview; do \
			yq -i '.image.tag = "$(SHA)"' services/$$svc/chart/$$f.yaml; \
		done; \
		echo ">>> $$svc : image.tag = $(SHA)"; \
	done

# Publie les images sur GHCR (nécessite `docker login ghcr.io` avec un PAT
# scope write:packages). Satisfait le livrable de l'étape 3.
push:
	@for svc in $(SERVICES); do \
		echo ">>> push $$svc:$(SHA)"; \
		docker push ghcr.io/$(GHCR_USER)/$$svc:$(SHA); \
	done

clean:
	kind delete cluster --name $(CLUSTER) 2>/dev/null || true
