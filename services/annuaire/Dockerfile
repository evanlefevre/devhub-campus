# Étape 3 du TP — image annuaire (Node.js).
# Contraintes respectées : multi-stage, ≤ 200 Mo, non-root (1001),
# pas de secret en ENV/ARG, LABEL oci.source, LOG_LEVEL honoré par l'app.

# ---- Stage 1 : build / install des dépendances ----
# Tag immuable (version complète) plutôt que `20-alpine` qui bouge à chaque patch.
FROM node:20.18.1-alpine3.20 AS build

WORKDIR /app

# package.json copié seul d'abord : le layer `npm ci` reste en cache tant que
# les dépendances ne changent pas, même quand le code change.
COPY package.json ./
RUN npm install --omit=dev && npm cache clean --force

COPY src/ ./src/

# ---- Stage 2 : image runtime ----
FROM node:20.18.1-alpine3.20 AS runtime

LABEL org.opencontainers.image.source="https://github.com/evanlefevre/devhub-campus"

WORKDIR /app

COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/src ./src
COPY --from=build /app/package.json ./

# UID 1001 aligné avec le securityContext.runAsUser du chart Helm.
RUN addgroup -g 1001 app && adduser -D -u 1001 -G app app
USER 1001

ENV PORT=8080 \
    LOG_LEVEL=info \
    NODE_ENV=production

EXPOSE 8080

CMD ["node", "src/index.js"]
