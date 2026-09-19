# evidence

Screenshots captured while doing the work. All twenty-three are embedded in the
submission report as Figures 2–25; they are kept here at full resolution as the
originals behind those figures.

`01`–`14` are Phase 1 (Docker) and appear throughout the report. `15`–`23` are
Phase 2 (Kubernetes) and appear together in Appendix B.

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


## Phase 2 — Kubernetes (Appendix B)

| File | What it shows | Report figure |
|---|---|---|
| `15-k8s-kind-installed.png` | kind 0.33.0 installed, and the twelve manifests in `k8s/` that `docker-compose.yml` became | 17 |
| `16-k8s-cluster-created.png` | `kind create cluster` — one control-plane and two workers on Kubernetes v1.37.0 | 18 |
| `17-k8s-ingress-controller.png` | ingress-nginx installed; an Ingress is only a rule until a controller acts on it | 19 |
| `18-k8s-cluster-inventory.png` | The cluster before the app: three nodes Ready, no Ingress yet | 20 |
| `19-k8s-manifests-applied.png` | `kubectl apply -f k8s/` creating all twenty objects in filename order | 21 |
| `20-k8s-rolling-replacement.png` | Pods replaced after a corrected manifest — old ReplicaSet draining, new one coming Ready | 22 |
| `21-k8s-all-running.png` | Six pods `1/1 Running`, four ClusterIP Services, every Deployment at its declared count | 23 |
| `22-k8s-ingress-and-portforward.png` | The stored Ingress routing `/` to `taskflow-web:http`, and `port-forward` as the alternative | 24 |
| `23-k8s-application-running.png` | The same images, now served by Kubernetes, with a task added through the cluster | 25 |

These nine are the full-resolution captures, same as `01`-`14`. The copies
embedded in the report were cropped to the terminal window and reduced to
1600 px wide first, so the document stays a reasonable size -- which is why a
figure in the report is tighter than the file here.

## One thing to know when reading these

The API image reads **240 MB** in the 17 September captures and **246 MB** in the
18 September ones. Both are genuine: `node:22-alpine` refreshed upstream between
the two sessions. Every row of the comparison table in the report was measured in
a single session, so that table is like for like. The report says so under
Figure 8.
