# TaskFlow — Phase 1: Docker

A small, realistic multi-service task tracker, fully containerized. What used to
need a hand-installed PostgreSQL, a hand-installed Redis and `node server.js` on
every developer machine now starts with one command.

```bash
cp .env.example .env && docker compose up --build
```

Then open **http://localhost:8080**.

This is Phase 1 of a two-phase mentoring track. Phase 2 takes these same images
to Kubernetes, so every choice here is deliberately boring and standard — see
[Phase 2](#phase-2) below. The full brief and the submission report are in
[`docs/`](./docs/).

---

## Contents

- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick start](#quick-start)
- [Project structure](#project-structure)
- [Configuration](#configuration)
- [Everyday commands](#everyday-commands)
- [Data persistence](#data-persistence)
- [Development mode](#development-mode)
- [Published images](#published-images)
- [Troubleshooting](#troubleshooting)
- [Phase 2](#phase-2)

---

## Architecture

Four services on one user-defined bridge network, `taskflow-net`. **Only the web
tier is published to the host** — the API, the database and the cache are
reachable only from inside the network.

```
            HOST                      docker network: taskflow-net
                              +---------------------------------------------+
  Browser --> localhost:8080 -->  taskflow-web          nginx:1.27-alpine   |
                              |   (nginx, :80)                              |
                              |         |  proxy_pass  /api/  and  /health   |
                              |         v                                   |
                              |   taskflow-api          node:22-alpine      |
                              |   (node, :4000, non-root uid 1000)          |
                              |       |                    |                |
                              |   SQL |                    | RESP (30s TTL) |
                              |       v                    v                |
                              |   taskflow-db          taskflow-cache       |
                              |   postgres:16-alpine   redis:7-alpine       |
                              +-------|-------------------------------------+
                                      |
                             named volume: taskflow-db-data
```

| Service | Image | Published | Role |
|---|---|---|---|
| `taskflow-web` | `nginx:1.27-alpine` | **8080 → 80** | Serves `index.html`; reverse-proxies `/api/` and `/health` |
| `taskflow-api` | `node:22-alpine` | no | Express REST API |
| `taskflow-db` | `postgres:16-alpine` | no | Persistent store, seeded from `init.sql` on first boot |
| `taskflow-cache` | `redis:7-alpine` | no | Caches the task list for 30 s |

Each service is documented in its own directory: [`api/`](./api/README.md),
[`web/`](./web/README.md).

---

## Prerequisites

- Docker Desktop or Docker Engine, with Compose v2
  (`docker version`, `docker compose version`)
- Nothing else. No local Node, PostgreSQL or Redis is required.

---

## Quick start

```bash
# 1. Create your local environment file from the template.
#    .env is gitignored and must never be committed.
cp .env.example .env

# 2. (Recommended) edit .env and replace the placeholder password.

# 3. Build and start the whole stack.
docker compose up --build
```

### Verify it

```bash
curl -s http://localhost:8080/health
# {"status":"ok"}

curl -s http://localhost:8080/api/tasks
# {"source":"db","tasks":[...]}   — "cache" on a repeat read within 30s

curl -s -X POST http://localhost:8080/api/tasks \
  -H 'Content-Type: application/json' \
  -d '{"title":"Try TaskFlow","description":"First task"}'
# 201 and the created task

curl -s http://localhost:8080/api/tasks
# back to "source":"db" — the POST invalidated the cache — with the new task
```

Or run all thirteen checks at once:

```bash
scripts/smoke-test.sh
```

---

## Project structure

```
TaskFlow/
├── docker-compose.yml           # BASE: four services, network, volume, limits
├── docker-compose.override.yml  # dev only: bind mounts, live reload
├── .env.example                 # template — copy to .env
│
├── api/                         # Node.js / Express API      -> api/README.md
│   ├── Dockerfile               #   multi-stage, non-root, healthcheck
│   ├── Dockerfile.debian        #   full-base variant, for the size comparison
│   ├── .dockerignore
│   ├── server.js
│   ├── package.json
│   ├── package-lock.json
│   └── db/init.sql              #   schema + seed, run by Postgres on first boot
│
├── web/                         # Nginx front end            -> web/README.md
│   ├── Dockerfile
│   ├── nginx.conf               #   static root + /api/ and /health proxy
│   └── index.html
│
├── scripts/                     # helpers                    -> scripts/README.md
│   ├── smoke-test.sh            #   up -> wait for health -> exercise API
│   └── build-images.sh          #   build + semver-tag both images
│
└── docs/                        # the brief and the write-up -> docs/README.md
    ├── TaskFlow_Docker_Mentoring_Task.pdf
    ├── TaskFlow_Phase1_Docker_Submission_Report.docx
    ├── debugging-exercise/      #   the Part 5 broken compose file
    └── evidence/                #   screenshots behind the report's figures
```

---

## Configuration

All configuration arrives as environment variables. Copy `.env.example` to
`.env` and edit; Compose reads it automatically.

| Variable | Default in the template | Used by |
|---|---|---|
| `DB_HOST` | `taskflow-db` | API — the Compose service name, which is also the DNS name |
| `DB_PORT` | `5432` | API |
| `DB_USER` | `taskflow` | API **and** Postgres |
| `DB_PASSWORD` | `changeme` | API **and** Postgres — **change this** |
| `DB_NAME` | `taskflow` | API **and** Postgres |
| `REDIS_HOST` | `taskflow-cache` | API |
| `REDIS_PORT` | `6379` | API |
| `PORT` | `4000` | API |
| `REGISTRY_NAMESPACE` | `taskflow` | Image tagging only |
| `TASKFLOW_VERSION` | `1.0.0` | Image tagging only |

`DB_USER`, `DB_PASSWORD` and `DB_NAME` are interpolated into **both** the API and
the database, so the two halves cannot drift apart.

> **`.env` is gitignored and never enters an image.** `api/.dockerignore`
> excludes it from the build context, because anyone who can pull an image can
> read its layers.

---

## Everyday commands

```bash
# Start / stop
docker compose up -d                        # dev (includes the override file)
docker compose -f docker-compose.yml up -d  # production-like (base file only)
docker compose ps
docker compose down                         # keeps the data volume
docker compose down -v                      # DELETES the data volume

# Logs
docker compose logs -f
docker compose logs -f taskflow-api

# Shell into a container
docker compose exec taskflow-api sh
docker compose exec taskflow-db psql -U taskflow -d taskflow

# Inspect the cache
docker compose exec taskflow-cache redis-cli GET tasks
docker compose exec taskflow-cache redis-cli DEL tasks

# Images and layers
docker images taskflow/taskflow-api
docker history taskflow/taskflow-api:1.0.0

# Networking
docker network inspect taskflow-net
```

---

## Data persistence

Task data lives in the named volume `taskflow-db-data`, mounted at
`/var/lib/postgresql/data`. It is independent of the container lifecycle, so a
crash, a restart or a full `down` and `up` all leave it intact:

```bash
docker compose down          # containers removed, volume kept
docker compose up -d         # your tasks are still there
```

Two things to know:

- **`docker compose down -v` deletes the volume.** That flag is the difference
  between a teardown and data loss.
- **`db/init.sql` runs on first boot only** — that is, while the data volume is
  still empty. Changing the schema afterwards means either a migration or
  `docker compose down -v` to re-initialise from scratch.

---

## Development mode

`docker-compose.override.yml` is loaded automatically by plain `docker compose up`
and adds local conveniences: live reload via `node --watch`, a bind mount of the
source, published database and cache ports, and `restart: "no"` so a crash stays
visible instead of looping.

None of it belongs in a real deployment, which is the whole point of the split —
the base file stays honest about how the stack actually runs:

```bash
docker compose up -d                        # base + override  (development)
docker compose -f docker-compose.yml up -d  # base only        (production-like)
```

---

## Published images

Both images are public on Docker Hub:

- https://hub.docker.com/r/nadeeshamedagama/taskflow-api
- https://hub.docker.com/r/nadeeshamedagama/taskflow-web

```bash
docker pull nadeeshamedagama/taskflow-api:1.0.0
docker pull nadeeshamedagama/taskflow-web:1.0.0
```

To build and tag your own, see [`scripts/README.md`](./scripts/README.md).

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `host not found in upstream "taskflow-api"` | Nginx started before the API existed | Handled by `depends_on: service_healthy`; if that was removed, put it back |
| `GET /api/tasks` returns `500` | Schema missing — the volume was created before `init.sql` was mounted | `docker compose down -v && docker compose up --build` |
| `password authentication failed` | `.env` changed after the volume was initialised; Postgres keeps the **original** credentials | `docker compose down -v` to re-initialise, or change it inside `psql` |
| `taskflow-api` stuck `starting` | Waiting on database or cache health | `docker compose ps`, then `docker compose logs taskflow-db` |
| `bind: address already in use` | Host port 8080 is taken | Free it, or change the host side of `"8080:80"` |
| Stale data for up to 30 s | The cache TTL | Wait it out, or `docker compose exec taskflow-cache redis-cli DEL tasks` |
| Tasks vanished | `docker compose down -v` removed the volume | Use plain `down` |

---

## Phase 2

Phase 2 redeploys these exact images to Kubernetes. Nothing here needs building
yet, but it explains why the Docker setup is shaped the way it is:

| This repo now | Kubernetes later |
|---|---|
| A container image per service | The image in a Pod's container spec |
| A Compose service | A Deployment + a Service |
| Service name for DNS (`taskflow-db`) | Service DNS name — identical idea |
| `env_file` / `environment:` | ConfigMap (non-secret) and Secret (secret) |
| Named volume `taskflow-db-data` | PersistentVolumeClaim + StatefulSet |
| `deploy.resources.limits` / `.reservations` | `resources.limits` / `resources.requests` |
| `healthcheck:` | `livenessProbe` and `readinessProbe` |
| `depends_on: service_healthy` | **No equivalent** — the app must tolerate absent dependencies |
| `ports: "8080:80"` | A ClusterIP Service + an Ingress |
| Image tag in a registry | The `image:` field every Pod spec pulls from |

The trade-offs behind each of these are discussed in §8 of the submission report.
