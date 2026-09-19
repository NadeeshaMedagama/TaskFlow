# taskflow-api

Node.js / Express REST API. Reads and writes tasks in PostgreSQL and caches the
task list in Redis for 30 seconds.

## Files

| File | Purpose |
|---|---|
| `server.js` | The whole application — `/health`, `GET /api/tasks`, `POST /api/tasks` |
| `package.json` | Dependencies: `express`, `pg`, `redis`, `cors` |
| `package-lock.json` | Required by `npm ci`; pins the exact dependency tree |
| `Dockerfile` | Multi-stage build on `node:22-alpine` — **this is the one that ships** |
| `Dockerfile.debian` | The same build on the full `node:22` base, kept only to reproduce the size comparison in the report (1.63 GB vs 246 MB) |
| `.dockerignore` | Keeps `node_modules`, `.env`, `.git`, `db/` and editor noise out of the build context |
| `db/init.sql` | Schema and seed data. Belongs to PostgreSQL, not to this image — Compose bind-mounts it into the database container |

## Endpoints

| Method | Path | Body | Response |
|---|---|---|---|
| `GET` | `/health` | — | `{"status":"ok"}` |
| `GET` | `/api/tasks` | — | `{"source":"db"\|"cache","tasks":[…]}` |
| `POST` | `/api/tasks` | `{"title":"…","description":"…"}` | `201` and the created task |

`GET /api/tasks` caches the list in Redis under the key `tasks` with a 30-second
TTL, so repeat reads report `"source":"cache"`. `POST` deletes that key, so the
next read comes fresh from the database. A missing `title` returns `400`.

If Redis is unreachable the API degrades rather than failing: `redisReady` stays
`false` and every read falls through to PostgreSQL.

## Configuration

Every value arrives as an environment variable — nothing is hard-coded and no
config file is read. Compose supplies them from the project's `.env`.

| Variable | Example | Notes |
|---|---|---|
| `DB_HOST` | `taskflow-db` | The **Compose service name**, which is also the DNS name |
| `DB_PORT` | `5432` | Defaults to 5432 if unset |
| `DB_USER` | `taskflow` | |
| `DB_PASSWORD` | — | The one genuinely secret value; never commit it |
| `DB_NAME` | `taskflow` | |
| `REDIS_HOST` | `taskflow-cache` | Compose service name |
| `REDIS_PORT` | `6379` | Defaults to 6379 if unset |
| `PORT` | `4000` | Defaults to 4000 if unset |

## The image

Two stages. `deps` installs production dependencies with `npm ci --omit=dev`;
`runtime` copies in only `node_modules`, `package.json` and `server.js`.

Three details are deliberate and worth keeping:

- **Manifests are copied before the source.** That keeps the dependency layer
  keyed to the dependency set alone, so editing `server.js` rebuilds in about
  1.3 s instead of re-running the install.
- **`--chown=node:node` on each `COPY`.** Copying as root and running a separate
  `chown -R` would write a second full copy of `node_modules` into a new layer —
  roughly 10.7 MB that no later instruction can remove.
- **The healthcheck uses the `node` binary already in the image** rather than
  installing `curl`, so it adds nothing to image size or attack surface.

The process runs as the image's built-in unprivileged `node` user (uid/gid 1000).

## Running it on its own

Normally you would just use `docker compose up` from the project root. To build
and run this service alone:

```bash
docker build -t taskflow-api:dev .
docker run --rm -p 4000:4000 --env-file ../.env taskflow-api:dev
```

It will start but return `500` on `/api/tasks` until a reachable PostgreSQL with
the `tasks` table exists — which is exactly what the Compose stack provides.
