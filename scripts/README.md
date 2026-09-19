# scripts

Two helper scripts. Both are safe to run from anywhere — each one resolves the
project root from its own location before doing anything.

## `smoke-test.sh` — verify the stack end to end

Brings the stack up, waits for every service to report healthy, exercises the
API, and reports pass/fail. It exits non-zero on any failure, so it works
unchanged as a CI gate.

```bash
scripts/smoke-test.sh              # production-like: base compose file only
scripts/smoke-test.sh --dev        # include docker-compose.override.yml
scripts/smoke-test.sh --no-build   # reuse existing images
scripts/smoke-test.sh --down       # tear the stack down when finished
```

| Environment variable | Default | Purpose |
|---|---|---|
| `BASE_URL` | `http://localhost:8080` | Where the web tier is published |
| `TIMEOUT` | `180` | Seconds to wait for health |

Thirteen checks run in total. Beyond the obvious ones it verifies the cache
contract in **both** directions — that a write invalidates the cache (the next
read reports `source=db`) and that the following read is served from Redis
(`source=cache`). A stack that returns stale data after a write would pass a
naive smoke test and fail this one.

## `build-images.sh` — build and tag for a registry

Builds both first-party images and tags them with a real semantic version, the
way something destined for a registry is tagged.

```bash
scripts/build-images.sh                          # build + tag locally
scripts/build-images.sh --version 1.1.0          # override the version
scripts/build-images.sh --namespace myuser       # override the namespace
scripts/build-images.sh --platform linux/amd64   # cross-build for a cluster
scripts/build-images.sh --no-cache               # force a clean rebuild
scripts/build-images.sh --push                   # build, tag, then push
```

Values resolve in this order, first match winning:

```
command-line flag  ->  environment variable  ->  .env  ->  built-in default
```

| Key | Default | Notes |
|---|---|---|
| `TASKFLOW_VERSION` | `1.0.0` | Must be `MAJOR.MINOR.PATCH`; validated before anything is built |
| `REGISTRY_NAMESPACE` | `taskflow` | A local placeholder — set it to your own Docker Hub user before pushing |

**It does not push unless asked.** `--push` is opt-in, and even then the script
prints what it is about to publish and requires you to type the version to
confirm. Pushing makes an image available to everyone who can read that
namespace, and that is hard to undo — tags can be deleted, but anything already
pulled stays pulled.

`latest` is tagged locally as a convenience but deliberately never pushed: a
moving tag is the wrong thing for a Pod spec to reference.

## A note on reading these scripts

Both use `${ARR[@]+"${ARR[@]}"}` rather than a bare `"${ARR[@]}"` when expanding
arrays. macOS ships bash 3.2, where expanding an *empty* array under `set -u` is
an unbound-variable error rather than an empty list. The guarded form is the
portable idiom, not noise.
