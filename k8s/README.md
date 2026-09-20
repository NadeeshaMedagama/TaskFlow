# Phase 2 — TaskFlow on Kubernetes

The same four services, the same two images, translated from `docker-compose.yml`
into Kubernetes objects and run on a local cluster.

**Nothing here was rebuilt.** `nadeeshamedagama/taskflow-api:1.0.0` and
`nadeeshamedagama/taskflow-web:1.0.0` are the artifacts Phase 1 produced and
pushed. The application source, the Dockerfiles and `docker-compose.yml` are
untouched — `docker compose up --build` still works exactly as before.

---

## Contents

- [The whole thing, in eight commands](#the-whole-thing-in-eight-commands)
- [The translation](#the-translation)
- [What Compose could not express](#what-compose-could-not-express)
- [Prerequisites](#prerequisites)
- [Deploy it — kind](#deploy-it--kind)
- [Deploy it — minikube](#deploy-it--minikube)
- [Verify](#verify)
- [The three demonstrations](#the-three-demonstrations)
- [Everyday commands](#everyday-commands)
- [Troubleshooting](#troubleshooting)
- [Teardown](#teardown)
- [File reference](#file-reference)
- [Deliberate gaps](#deliberate-gaps)

---

## The whole thing, in eight commands

For when you have done it once already and just want it back. Every step is
explained in full further down; run these from the repository root.

```bash
brew install kind                                              # once
kind create cluster --config k8s/cluster/kind-cluster.yaml     # ~2 min

kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait -n ingress-nginx --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller --timeout=180s

kubectl apply -f k8s/
kubectl -n taskflow rollout status deployment/taskflow-api --timeout=300s

curl -s http://localhost:8080/health; echo                     # {"status":"ok"}
open http://localhost:8080
```

Already have minikube and would rather not install kind? Jump to
[Deploy it — minikube](#deploy-it--minikube). Want neither an ingress
controller nor a tunnel? [port-forward](#no-ingress-controller) works on any
cluster and installs nothing.

---

## The translation

| `docker-compose.yml` | Kubernetes | File |
|---|---|---|
| `services:` × 4 | 4 × `Deployment` | `05`–`08` |
| service name on the bridge network | `Service` (ClusterIP) + cluster DNS | `05`–`08` |
| `networks: taskflow-net` | `Namespace` | `00` |
| `env_file: .env` (connection details) | `ConfigMap` | `01` |
| `env_file: .env` (credentials) | `Secret` | `02` |
| `./api/db/init.sql:/docker-entrypoint-initdb.d/…` | `ConfigMap` mounted as a volume | `03` |
| `volumes: taskflow-db-data` | `PersistentVolumeClaim` | `04` |
| `ports: ["8080:80"]` | `Ingress` + an ingress controller | `09` |
| `deploy.resources.limits` | `resources.limits` | each Deployment |
| `deploy.resources.reservations` | `resources.requests` | each Deployment |
| `healthcheck:` | `startupProbe` + `readinessProbe` + `livenessProbe` | each Deployment |
| `depends_on: condition: service_healthy` | `initContainers` that wait on the Service | `07`, `08` |
| *no* `ports:` on the datastores | `NetworkPolicy` (must be stated, not omitted) | `11` |
| — (no equivalent) | `HorizontalPodAutoscaler` | `10` |

### Four translations worth reading twice

**One healthcheck became three probes.** Compose had a single check doing three
jobs. Kubernetes separates them, and the distinction is the whole point:
`readinessProbe` failing pulls the pod out of the Service's endpoints and kills
nothing; `livenessProbe` failing restarts the container. Get them the wrong way
round and a momentarily busy database gets shot instead of drained.
`startupProbe` replaces Compose's `start_period`, and does it better — a slow
first boot extends the allowance rather than racing a fixed timer.

**`depends_on` has no equivalent, on purpose.** Kubernetes expects a pod to
tolerate its dependencies being absent and be restarted until they are not.
The init containers in `07` and `08` restore orderly startup anyway, because
they are cheap and they turn a baffling `CrashLoopBackOff` into a legible
`Init:0/2`. For `taskflow-web` it is not optional: nginx resolves its
`proxy_pass` upstream once, at startup, and refuses to start if the name does
not resolve.

**Isolation flipped from omission to declaration.** In Compose the datastores
were protected by the *absence* of a `ports:` block. A Kubernetes cluster is
flat by default — every pod can reach every other pod — so the same protection
has to be written down. That is `11-networkpolicy.yaml`. Read the caveat in it
before you trust it.

**Memory units changed, CPU did not.** Compose wrote `512M` (SI megabytes,
10⁶); Kubernetes convention is `512Mi` (mebibytes, 2²⁰). Every memory value
here is therefore **4.9 % larger** than its Compose counterpart — never
smaller, which is the property that matters. CPU is unitless in both, so
`0.75` → `750m` is exact.

---

## What Compose could not express

Three things, and they are the reason Phase 2 exists:

| | Compose | Kubernetes |
|---|---|---|
| **Self-healing** | `restart: unless-stopped` restarts the one container you had, after the outage | A ReplicaSet keeps *N* pods alive; losing one is survivable because another is already serving |
| **Rolling updates** | `docker compose up -d` stops the old container, then starts the new one | `maxUnavailable: 0` + a readiness probe = a deploy that costs zero capacity |
| **Horizontal scaling** | no concept of replicas at all | `kubectl scale`, or an HPA that does it from measured CPU |

[Exercises for all three are below.](#the-three-demonstrations)

---

## Prerequisites

```bash
kubectl version --client        # 1.28 or newer
docker version                  # kind and minikube both run the cluster in Docker
```

Plus **one** of:

```bash
brew install kind               # recommended on macOS — see why below
brew install minikube
```

> **Why kind is recommended here.** `k8s/cluster/kind-cluster.yaml` maps host
> port **8080** to the cluster's ingress port, so the app ends up at
> **http://localhost:8080** — the exact address Phase 1 used. On macOS,
> minikube's Ingress needs a separate `minikube tunnel` process running as
> root. Both work; kind has fewer moving parts. If you would rather install no
> ingress controller at all, skip to [port-forward](#no-ingress-controller).

**You do not need to build anything.** Both images are public on Docker Hub and
`imagePullPolicy: IfNotPresent` will pull them. Only load images manually if
you have built your own locally.

---

## Deploy it — kind

### 1. Create the cluster

```bash
cd /path/to/TaskFlow
kind create cluster --config k8s/cluster/kind-cluster.yaml
```

Three nodes: one control-plane (labelled `ingress-ready=true` and publishing
host `8080` → node `80`) and two workers, so the anti-affinity rules have
somewhere to spread replicas to.

```bash
kubectl config use-context kind-taskflow
kubectl get nodes
```

Creating the cluster takes about two minutes the first time, less afterwards
once the node image is cached. `kubectl get nodes` should list three nodes,
all `Ready`; if a worker is still `NotReady` give it another twenty seconds.

### 2. Install the ingress controller

An `Ingress` object is only a routing *rule*. Something has to act on it:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s
```

Wait for `pod/ingress-nginx-controller-... condition met` before going on. The
controller takes 30-60 seconds to become ready, and applying the Ingress
before it exists simply means nothing serves the rule.

### 3. (Optional) Load locally built images

Skip this unless you built your own:

```bash
kind load docker-image nadeeshamedagama/taskflow-api:1.0.0 --name taskflow
kind load docker-image nadeeshamedagama/taskflow-web:1.0.0 --name taskflow
```

### 4. Apply the manifests

```bash
kubectl apply -f k8s/
```

Expect 20 objects created across 12 files: 1 Namespace, 2 ConfigMaps for
configuration plus 1 for the schema, 1 Secret, 1 PersistentVolumeClaim, 4
Deployments, 4 Services, 1 Ingress, 1 HorizontalPodAutoscaler and 5
NetworkPolicies.

The files are numbered because `kubectl apply -f <dir>` processes them in
filename order, and order matters: the Namespace must exist before anything
goes into it, and the ConfigMap and Secret before the pods that mount them.
`k8s/cluster/` is skipped — `-f <dir>` is not recursive, which is exactly why
the kind config lives there.

### 5. Wait for it

```bash
kubectl -n taskflow rollout status deployment/taskflow-db    --timeout=180s
kubectl -n taskflow rollout status deployment/taskflow-cache --timeout=120s
kubectl -n taskflow rollout status deployment/taskflow-api   --timeout=180s
kubectl -n taskflow rollout status deployment/taskflow-web   --timeout=120s
```

Watch it happen instead, if you prefer:

```bash
kubectl -n taskflow get pods -w
```

Budget 60-90 seconds on a first run -- most of it is pulling four images. A
second run on the same cluster is nearer 20.

You will see the API pods sit in `Init:0/2` until Postgres and Redis report
Ready. That is the `depends_on` translation doing its job. `taskflow-web`
follows the same pattern at `Init:0/1`, waiting on the API.

### 6. Open it

**http://localhost:8080**

---

## Deploy it — minikube

```bash
minikube start --profile taskflow --cpus 4 --memory 6144 --driver docker
minikube addons enable ingress --profile taskflow
kubectl config use-context taskflow

# optional, only for locally built images
minikube image load nadeeshamedagama/taskflow-api:1.0.0 --profile taskflow
minikube image load nadeeshamedagama/taskflow-web:1.0.0 --profile taskflow

kubectl apply -f k8s/
kubectl -n taskflow rollout status deployment/taskflow-api --timeout=180s
```

Note the address on this path is plain **http://localhost**, with no `:8080` --
the tunnel binds port 80 directly, where kind's config maps 8080.

Then, in a **second terminal** (it must keep running, and it will ask for your
password):

```bash
minikube tunnel --profile taskflow
```

Open **http://localhost**.

### No ingress controller

Works on any cluster, installs nothing, needs no tunnel:

```bash
kubectl -n taskflow port-forward svc/taskflow-web 8080:80
```

Open **http://localhost:8080**. Leave the command running.

---

## Verify

```bash
kubectl -n taskflow get all
kubectl -n taskflow get pvc,configmap,secret,ingress
```

Then exercise the API exactly as Phase 1's smoke test did — through the web
tier, which proves nginx's `proxy_pass` is still resolving `taskflow-api`:

```bash
BASE=http://localhost:8080          # or http://localhost with minikube tunnel

curl -s $BASE/health;      echo     # {"status":"ok"}
curl -s $BASE/api/tasks;   echo     # {"source":"db","tasks":[…3 seeded rows…]}
curl -s $BASE/api/tasks;   echo     # {"source":"cache",…}  <- Redis is working

curl -s -X POST $BASE/api/tasks \
  -H 'Content-Type: application/json' \
  -d '{"title":"deployed to kubernetes","description":"phase 2"}'; echo

curl -s $BASE/api/tasks;   echo     # source is "db" again — the write invalidated the key
```

Three seeded rows means the `init.sql` ConfigMap was mounted and applied.
`source` flipping `db` → `cache` → `db` means the cache and its invalidation
survived the translation.

### Prove the data is on the volume, not in the pod

```bash
kubectl -n taskflow delete pod -l app.kubernetes.io/name=taskflow-db
kubectl -n taskflow rollout status deployment/taskflow-db
curl -s $BASE/api/tasks; echo      # your task is still there
```

The pod was destroyed and rebuilt; the PersistentVolumeClaim was not.

---

## The three demonstrations

### 1. Self-healing

In one terminal, hammer the endpoint:

```bash
while true; do curl -s -o /dev/null -w "%{http_code} " http://localhost:8080/health; sleep 0.3; done
```

In another, destroy a pod:

```bash
# Pick ONE replica and destroy it. Deleting by label alone would take out both
# and there would be nothing left to serve the loop -- which is the opposite
# of the point.
POD=$(kubectl -n taskflow get pods -l app.kubernetes.io/name=taskflow-api \
        -o jsonpath='{.items[0].metadata.name}')
kubectl -n taskflow delete pod "$POD"
kubectl -n taskflow get pods -w
```

The first terminal keeps printing `200`. The ReplicaSet notices it is one pod
short and creates a replacement; the surviving replica serves throughout.
Compose's `restart:` could only have restarted the single container, *after*
the requests had already failed.

### 2. Rolling update

```bash
# Roll forward. This one line is the entire deploy.
kubectl -n taskflow set image deployment/taskflow-api api=nadeeshamedagama/taskflow-api:1.0.1
kubectl -n taskflow rollout status deployment/taskflow-api

# Watch the old and new ReplicaSets hand over
kubectl -n taskflow get rs -w

# Where it came from, and how to go back
kubectl -n taskflow rollout history deployment/taskflow-api
kubectl -n taskflow rollout undo deployment/taskflow-api
```

Keep the `curl` loop running while you do it: still all `200`. That is
`maxUnavailable: 0` plus the readiness probe — a new pod must answer `/health`
before an old one is allowed to go.

> No `1.0.1` tag published yet? Then the new pods will sit in `ImagePullBackOff`
> and — this is the interesting part — **the old ones keep serving**. The
> rollout stalls instead of taking the app down, and `rollout undo` cleans up.
> Compose would have stopped the working container first.

### 3. Horizontal scaling

Manually:

```bash
kubectl -n taskflow scale deployment/taskflow-api --replicas=5
kubectl -n taskflow get pods -o wide        # spread across nodes by podAntiAffinity
kubectl -n taskflow scale deployment/taskflow-api --replicas=2
```

Automatically, from measured CPU. First install metrics-server — the HPA has
nothing to read without it:

```bash
# minikube
minikube addons enable metrics-server --profile taskflow

# kind
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
# kind's kubelet serving certs are not signed by the cluster CA, so metrics-server
# will not scrape until you tell it not to verify them:
kubectl -n kube-system patch deployment metrics-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
kubectl -n kube-system rollout status deployment/metrics-server
```

Then:

```bash
# Remove `replicas: 2` from 07-api.yaml first — see the note at the top of 10-hpa.yaml
kubectl apply -f k8s/10-hpa.yaml
kubectl -n taskflow get hpa -w
```

Generate load in another terminal:

```bash
kubectl -n taskflow run load --rm -it --image=busybox:1.36 --restart=Never -- \
  sh -c 'while true; do wget -q -O /dev/null http://taskflow-api:4000/api/tasks; done'
```

Watch `TARGETS` climb past `70%` and `REPLICAS` follow. Ctrl-C the load and it
scales back down after the five-minute stabilisation window in `10-hpa.yaml` —
deliberately slow, so a lull between bursts does not cause flapping.

---

## Everyday commands

```bash
# What is running
kubectl -n taskflow get pods -o wide
kubectl -n taskflow get all

# Logs
kubectl -n taskflow logs -l app.kubernetes.io/name=taskflow-api --tail=50 -f
kubectl -n taskflow logs -l app.kubernetes.io/name=taskflow-api --previous   # after a crash

# Why is this pod unhappy
kubectl -n taskflow describe pod <name>
kubectl -n taskflow get events --sort-by=.lastTimestamp | tail -20

# Into the database, the way `docker compose exec` did
kubectl -n taskflow exec -it deploy/taskflow-db -- \
  psql -U taskflow -d taskflow -c 'SELECT * FROM tasks;'

# Into the cache
kubectl -n taskflow exec -it deploy/taskflow-cache -- redis-cli KEYS '*'

# Reach a datastore from your laptop (they are ClusterIP on purpose)
kubectl -n taskflow port-forward svc/taskflow-db 5432:5432

# Re-read config after editing 01-configmap.yaml or 02-secret.yaml.
# envFrom is read at container start, so pods must be restarted to see changes.
kubectl apply -f k8s/01-configmap.yaml
kubectl -n taskflow rollout restart deployment/taskflow-api

# What actually got applied
kubectl -n taskflow get deploy taskflow-api -o yaml | less
kubectl diff -f k8s/                      # dry-run diff against the live cluster
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| API pods stuck in `Init:0/2` | Postgres or Redis is not Ready yet | Normal for ~30 s on first boot. If it persists: `kubectl -n taskflow describe pod -l app.kubernetes.io/name=taskflow-db` |
| `ImagePullBackOff` | Tag does not exist, or a locally built image was never loaded | `kind load docker-image …` / `minikube image load …`, or fix the tag |
| DB pod `Pending`, event says *no persistent volumes available* | No default StorageClass | `kubectl get storageclass` — kind and minikube both ship one; if empty, your cluster is unusual |
| DB or cache `CrashLoopBackOff`, logs say *Operation not permitted* (`setpriv: setresuid failed`, `chown: ... Operation not permitted`) | `capabilities: drop: ["ALL"]` with nothing added back. These images start as root, fix ownership, then drop to their own user -- each step needs a capability | Keep the `add: [CHOWN, DAC_OVERRIDE, FOWNER, SETGID, SETUID]` list in `05`/`06`/`08` |
| DB pod `CrashLoopBackOff`, logs mention *directory not empty* | Volume reused from a different Postgres | The `PGDATA` subdirectory in `05-db.yaml` prevents this; if you hit it, delete the PVC and start clean |
| `curl` returns *connection refused* | Ingress controller not installed, or not finished starting | `kubectl -n ingress-nginx get pods`, or use [port-forward](#no-ingress-controller) |
| Ingress exists but 404s | `ingressClassName` does not match the installed controller | `kubectl get ingressclass` and put that name in `09-ingress.yaml` |
| Web pods `CrashLoopBackOff`, logs say *host not found in upstream* | The API Service did not exist when nginx started | The init container prevents this; if you removed it, `kubectl -n taskflow rollout restart deployment/taskflow-web` |
| `kubectl get hpa` shows `<unknown>/70%` | metrics-server missing, or not scraping | See [horizontal scaling](#3-horizontal-scaling) — on kind it needs `--kubelet-insecure-tls` |
| NetworkPolicies appear to do nothing | kind/minikube default CNI does not enforce them | Expected. See the caveat in `11-networkpolicy.yaml` |
| Pods `Pending`, *Insufficient cpu* | Cluster smaller than the sum of `requests` | `minikube start --cpus 4 --memory 6144`, or scale replicas down |

---

## Teardown

```bash
# Delete the app but keep the cluster.
# NOTE: this deletes the Namespace, which cascades to the PVC and the data.
kubectl delete -f k8s/

# Keep the data instead
kubectl -n taskflow delete deploy,svc,ingress,hpa,netpol --all

# Delete the cluster entirely
kind delete cluster --name taskflow
minikube delete --profile taskflow
```

---

## File reference

| File | Contains |
|---|---|
| `00-namespace.yaml` | `Namespace taskflow` — the boundary and the DNS domain |
| `01-configmap.yaml` | Non-secret config: hosts, ports, `NODE_ENV` |
| `02-secret.yaml` | `DB_USER`, `DB_PASSWORD`. **Local-cluster defaults — read the header before using this anywhere real** |
| `03-db-init-configmap.yaml` | `init.sql`, mounted into `/docker-entrypoint-initdb.d` |
| `04-db-pvc.yaml` | 2 Gi `ReadWriteOnce` claim for Postgres |
| `05-db.yaml` | Postgres Deployment (`strategy: Recreate`) + ClusterIP Service |
| `06-cache.yaml` | Redis Deployment + Service |
| `07-api.yaml` | API Deployment (2 replicas, rolling update, 2 init containers) + Service |
| `08-web.yaml` | nginx Deployment (2 replicas) + Service |
| `09-ingress.yaml` | The way in |
| `10-hpa.yaml` | **Optional.** CPU/memory autoscaler. Needs metrics-server |
| `11-networkpolicy.yaml` | **Optional.** Default-deny + four explicit allows. Needs a CNI that enforces them |
| `cluster/kind-cluster.yaml` | kind cluster definition. **Not a Kubernetes object — never pass it to `kubectl`** |

Validated with `kubeconform -strict` against the Kubernetes 1.31 schemas:
20 resources, 0 invalid.

---

## Deliberate gaps

Worth knowing, so none of these reads as an oversight:

- **Postgres is a Deployment, not a StatefulSet.** At one replica against one
  pre-declared PVC the two behave identically, and the brief maps a Compose
  service to a Deployment. The moment you want a second Postgres — a replica,
  not a copy — this must become a StatefulSet with a `volumeClaimTemplate`.
- **No TLS.** The Ingress is plain HTTP. Real clusters terminate TLS there,
  usually with cert-manager.
- **The API does not shut down gracefully.** `node` is PID 1 in that image, and
  PID 1 ignores signals it has no handler for — which is precisely why Compose
  set `init: true`. Kubernetes has no equivalent, so the container is SIGKILLed
  at the end of its grace period. The `preStop` hook in `07-api.yaml` keeps
  in-flight requests from being dropped; the real fix is a
  `process.on('SIGTERM', …)` handler in `server.js`.
- **Secrets are base64, not encrypted.** A Kubernetes Secret keeps credentials
  *separable* — RBAC'd apart, rotatable on their own — not *secret* from anyone
  who can read the namespace. Sealed Secrets or an external store is the next
  step.
- **One HPA, on the API only.** The web tier could have one too; Redis and
  Postgres cannot be scaled this way at all, for reasons noted in their files.
