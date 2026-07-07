# Étape 3 du TP — image notif (Go).
# Binaire statique (CGO off) + distroless/static : image finale ~10 Mo.
# Compromis des runtimes possibles (cf. RAPPORT.md) :
#   - scratch     : le plus petit, mais ni CA certs ni tzdata ni /etc/passwd ;
#   - distroless  : CA + tzdata + user nonroot fournis, pas de shell (pas de debug exec) ;
#   - alpine      : shell disponible pour debug, mais +5 Mo et surface d'attaque plus large.

# ---- Stage 1 : build du binaire Go ----
FROM golang:1.22-alpine AS build

WORKDIR /src

# go.mod copié seul d'abord pour garder le cache de modules entre deux builds.
# (pas de go.sum : le module n'a aucune dépendance externe)
COPY go.mod ./
RUN go mod download

COPY cmd/ ./cmd/
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/notif ./cmd

# ---- Stage 2 : runtime minimal ----
FROM gcr.io/distroless/static:nonroot AS runtime

LABEL org.opencontainers.image.source="https://github.com/evanlefevre/devhub-campus"

COPY --from=build /out/notif /notif

ENV PORT=8080 \
    LOG_LEVEL=info

EXPOSE 8080

# USER nonroot:nonroot (UID 65532) est déjà l'utilisateur par défaut de
# distroless:nonroot — le chart Helm doit être aligné sur 65532.
ENTRYPOINT ["/notif"]
