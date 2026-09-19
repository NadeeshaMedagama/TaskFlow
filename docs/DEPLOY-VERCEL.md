# Deploying TaskFlow to Vercel

**Time: about 10 minutes. Cost: nothing — every service below has a free tier.**

---

## First, what changes and why

Vercel does not run containers. It runs *functions*: your code is imported,
called once per request, and frozen again. So the four-container stack cannot
be lifted onto it as-is — three of the four pieces are replaced:

| Under Docker | On Vercel | Why |
|---|---|---|
| `taskflow-web` (nginx) | Vercel's CDN + `vercel.json` routes | No container to run nginx in. `vercel.json` does the `/api/` proxying that `nginx.conf` did. |
| `taskflow-api` (Node) | One serverless function | The same Express app, imported instead of listened on. |
| `taskflow-db` (Postgres container) | **A managed Postgres** | A container's disk disappears between requests. The database has to live somewhere that persists. |
| `taskflow-cache` (Redis container) | **Managed Redis, or nothing** | Same reason. The cache is optional — without it every read just goes to Postgres. |

Nothing about the Docker setup was removed to make this work. `docker compose
up --build` behaves exactly as it did before; the code simply accepts a
connection string in addition to the discrete `DB_*` variables, and only uses
the serverless path when it detects one.

---

## Step 1 — Create the database

You need one managed Postgres. Easiest is through Vercel itself:

1. Go to **[vercel.com/dashboard](https://vercel.com/dashboard) → Storage → Create Database**
2. Choose **Neon (Serverless Postgres)** → **Continue** → pick a region near you → **Create**

That's it. Vercel will wire the connection string into your project
automatically in Step 3.

> **Using Neon or Supabase directly instead?** Fine — just copy their
> **pooled** connection string (Neon's has `-pooler` in the hostname; Supabase
> calls it *Connection pooling*, port `6543`). The pooled one matters: serverless
> opens and drops connections constantly and a direct connection will exhaust
> the database's connection limit.

---

## Step 2 — Import the repository

1. Go to **[vercel.com/new](https://vercel.com/new)**
2. **Import** `NadeeshaMedagama/TaskFlow`
3. **Change nothing** on the configuration screen. Framework Preset stays
   *Other*, and you can ignore the Build and Output settings — `vercel.json`
   already defines them, and Vercel will tell you so with a notice.
4. Click **Deploy**

The first deploy may show errors on `/api/tasks` until Step 3 is done. That is
expected.

---

## Step 3 — Connect the database

**If you created the database in Step 1 via Vercel:**

Project → **Storage** → your database → **Connect Project** → select this
project → **Connect**. Vercel injects the connection string for you.

**If you are using an outside provider:**

Project → **Settings** → **Environment Variables** → add:

| Name | Value | Environments |
|---|---|---|
| `DATABASE_URL` | your pooled connection string | Production, Preview, Development |

Then **Deployments → ⋯ → Redeploy** so the new variable is picked up.

> The schema creates itself. On its first request the API notices the `tasks`
> table is missing and runs `api/db/init.sql` — the very same file Postgres
> runs from `/docker-entrypoint-initdb.d` under Compose. No migration step, no
> SQL to paste.

---

## Step 4 — Check it works

Open your deployment URL. You should see the TaskFlow page with three seeded
tasks, and adding one through the form should work.

```bash
curl https://YOUR-APP.vercel.app/health
# {"status":"ok"}

curl https://YOUR-APP.vercel.app/api/tasks
# {"source":"db","tasks":[{"id":1,...}]}
```

`"source":"db"` on every read is correct and expected until you do Step 5.

---

## Step 5 — Add the cache (optional)

Skip this and everything still works — you just lose the caching the project
demonstrates, and `source` stays `db` forever.

1. Vercel dashboard → **Storage → Create Database → Upstash (Redis)** → **Create**
2. **Connect Project** → this project
3. **Redeploy**

Upstash speaks the normal Redis protocol over TLS, so the same `redis` client
the container uses works unchanged.

Now a second read of `/api/tasks` returns `"source":"cache"`, exactly as the
smoke test asserts under Docker.

---

## Environment variables, in full

| Variable | Required | What it is |
|---|---|---|
| `DATABASE_URL` | **yes** | Pooled Postgres connection string. `POSTGRES_URL` is accepted too — that is the name Vercel's own integrations inject. |
| `REDIS_URL` | no | e.g. `rediss://default:TOKEN@eu1-xxx.upstash.io:6379`. `KV_URL` is accepted too. Omit it to run without a cache. |

The `DB_HOST` / `DB_USER` / `DB_PASSWORD` / `DB_NAME` variables from `.env` are
**not** used on Vercel. They are the Compose path. If both are present, the
connection string wins.

---

## Deploying from the terminal instead

```bash
npm i -g vercel
vercel login
vercel link                      # pick or create the project
vercel env add DATABASE_URL      # paste the pooled connection string
vercel --prod
```

---

## If something is wrong

| Symptom | Cause | Fix |
|---|---|---|
| `/api/tasks` returns 500, `/health` returns 200 | `DATABASE_URL` is missing or wrong — the app is up, the database is not reachable | Check Settings → Environment Variables, then redeploy. Runtime Logs show the exact Postgres error. |
| `500` with `no pg_hba.conf entry` or an SSL error | Your provider needs TLS, or you used the direct URL | Use the **pooled** connection string; TLS is already enabled in code. |
| `too many connections` | Direct (unpooled) connection string | Switch to the pooled one. |
| `relation "tasks" does not exist` | Bootstrap could not run | Run `api/db/init.sql` once in your provider's SQL editor. |
| Page loads but is empty, no errors | Database is reachable and empty | Normal on a brand-new database *if* the seed was skipped; run `api/db/init.sql`. |
| Build notice about `vercel.json` overriding settings | Not an error | Expected — `builds` in `vercel.json` is deliberate. |

Logs: Vercel dashboard → your deployment → **Runtime Logs**.

---

## What is in the repository for this

| File | Role |
|---|---|
| `vercel.json` | Routing and build definition. The Vercel counterpart to `web/nginx.conf`. |
| `api/index.js` | Nine lines: hands the Express app to Vercel. |
| `.vercelignore` | Keeps `docs/`, `.github/`, Docker files and the 4.5 MB of report screenshots out of the deployment. |
| `api/server.js` | Unchanged routes. Now also reads a connection string, treats the cache as optional, and creates the schema when it is absent. |

None of it affects `docker compose up`.
