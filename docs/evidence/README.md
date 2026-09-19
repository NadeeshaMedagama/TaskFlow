# evidence

Screenshots captured while doing the work. All fourteen are embedded in the
submission report as Figures 2–16; they are kept here at full resolution as the
originals behind those figures.

Files were renamed from their capture timestamps to describe what they show. The
numbering follows the order the work was done in, not the order they appear in
the report.

| File | What it shows | Report figure |
|---|---|---|
| `01-api-image-build.png` | The API image building — `.dockerignore` loaded, 42.19 kB context transferred, `npm ci --omit=dev` in the `deps` stage | 2, 9 |
| `02-api-image-tagged.png` | The same build finishing — the `runtime` stage copying only what it needs, tagged `1.0.0` and `latest` | 3 |
| `03-web-image-build.png` | The frontend image building on `nginx:1.27-alpine` | 4 |
| `04-web-image-tagged.png` | `nginx.conf` and `index.html` copied in, tagged `1.0.0` and `latest` | 5 |
| `05-compose-up-build.png` | `docker compose up --build` — the single command from the brief | 12 |
| `06-compose-up-running.png` | Both images built, all four containers created, Redis and PostgreSQL logs streaming | 13 |
| `07-smoke-test-preflight.png` | `smoke-test.sh` checking Docker, Compose v2 and `.env` before starting | 14 |
| `08-smoke-test-passed.png` | Every container healthy, then **13 checks passed, 0 failed** | 15 |
| `09-docker-tag-for-registry.png` | Re-tagging the local images into the Docker Hub namespace | 10 |
| `10-docker-push-succeeded.png` | The push completing, with the digest line | 11 |
| `11-application-running.png` | TaskFlow in the browser, reads served from Redis (`source: cache`) | 16 |
| `12-docker-desktop-images.png` | Docker Desktop's local image inventory | 8 |
| `13-image-size-variants.png` | The four measured build variants on disk — 1.63 GB / 254 MB / 246 MB / 246 MB | 6 |
| `14-image-size-debian-vs-alpine.png` | `taskflow-api:debian` at 1.63 GB against the shipped image at 246 MB | 7 |

## One thing to know when reading these

The API image reads **240 MB** in the 17 September captures and **246 MB** in the
18 September ones. Both are genuine: `node:22-alpine` refreshed upstream between
the two sessions. Every row of the comparison table in the report was measured in
a single session, so that table is like for like. The report says so under
Figure 8.
