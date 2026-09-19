#!/usr/bin/env bash
#
# build-images.sh -- build and tag the two first-party TaskFlow images with a
# real semantic version, the way something destined for a registry is tagged.
#
# It does NOT push by default. Push is opt-in via --push, and even then it
# asks for confirmation first, because pushing publishes the image to everyone
# who can read that namespace.
#
# Usage:
#   scripts/build-images.sh                       # build + tag locally
#   scripts/build-images.sh --version 1.1.0       # override the version
#   scripts/build-images.sh --namespace myuser    # override the namespace
#   scripts/build-images.sh --platform linux/amd64  # cross-build for a cluster
#   scripts/build-images.sh --no-cache            # force a clean rebuild
#   scripts/build-images.sh --push                # build, tag, then push (asks)
#
# Values are resolved in this order, first match wins:
#   command-line flag  ->  environment variable  ->  .env  ->  built-in default
#
# Environment / .env keys:
#   TASKFLOW_VERSION      default 1.0.0
#   REGISTRY_NAMESPACE    default taskflow   (set to your Docker Hub user, or
#                                             ghcr.io/<user>, before pushing)

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd -- "$SCRIPT_DIR/.."

# Read one key out of .env without sourcing it -- sourcing would execute
# whatever happens to be in there.
env_value() {
  local key=$1
  [[ -f .env ]] || return 0
  sed -n "s/^[[:space:]]*${key}=//p" .env | tail -n1 | sed 's/^["'\'']//; s/["'\'']$//'
}

VERSION=""
NAMESPACE=""
PLATFORM=""
NO_CACHE=0
DO_PUSH=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)   VERSION=${2:?--version needs a value}; shift 2 ;;
    --namespace) NAMESPACE=${2:?--namespace needs a value}; shift 2 ;;
    --platform)  PLATFORM=${2:?--platform needs a value}; shift 2 ;;
    --no-cache)  NO_CACHE=1; shift ;;
    --push)      DO_PUSH=1; shift ;;
    -h|--help)   sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)           echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

VERSION=${VERSION:-${TASKFLOW_VERSION:-$(env_value TASKFLOW_VERSION)}}
VERSION=${VERSION:-1.0.0}
NAMESPACE=${NAMESPACE:-${REGISTRY_NAMESPACE:-$(env_value REGISTRY_NAMESPACE)}}
NAMESPACE=${NAMESPACE:-taskflow}

if ! [[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "error: '$VERSION' is not a semantic version (expected MAJOR.MINOR.PATCH)" >&2
  exit 2
fi

if [[ -t 1 ]]; then
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BOLD=''; DIM=''; RESET=''
fi

step() { printf '\n%s==> %s%s\n' "$BOLD" "$1" "$RESET"; }

if ! docker version --format '{{.Server.Version}}' >/dev/null 2>&1; then
  echo "error: Docker daemon is not reachable. Start Docker Desktop and retry." >&2
  exit 1
fi

# service-name : build-context
IMAGES=(
  "taskflow-api:api"
  "taskflow-web:web"
)

# Guarded expansion below, not a bare "${BUILD_ARGS[@]}": macOS ships bash
# 3.2, where expanding an EMPTY array under `set -u` is an unbound-variable
# error rather than an empty list. ${ARR[@]+"${ARR[@]}"} is the portable idiom.
BUILD_ARGS=()
(( NO_CACHE )) && BUILD_ARGS+=(--no-cache)
[[ -n "$PLATFORM" ]] && BUILD_ARGS+=(--platform "$PLATFORM")

step "Building $NAMESPACE/{taskflow-api,taskflow-web}:$VERSION"
[[ -n "$PLATFORM" ]] && printf '%splatform: %s%s\n' "$DIM" "$PLATFORM" "$RESET"

for entry in "${IMAGES[@]}"; do
  name=${entry%%:*}
  context=${entry##*:}
  printf '\n%s--- %s (context: ./%s) ---%s\n' "$DIM" "$name" "$context" "$RESET"
  # Both tags in one build: same image id, two names. `latest` is a
  # convenience for local work -- the versioned tag is the one a Pod spec
  # should ever reference, since `latest` is a moving target.
  docker build ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"} \
    -t "$NAMESPACE/$name:$VERSION" \
    -t "$NAMESPACE/$name:latest" \
    "./$context"
done

step "Built"
docker images \
  --filter "reference=$NAMESPACE/taskflow-*" \
  --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}'

if (( ! DO_PUSH )); then
  step "Not pushed"
  cat <<NOTE
${DIM}Nothing has been published. Review the images first:

    docker history $NAMESPACE/taskflow-api:$VERSION
    docker run --rm $NAMESPACE/taskflow-api:$VERSION node --version

When you are ready, log in and push -- or re-run this script with --push:

    docker login                     # or: docker login ghcr.io
    docker push $NAMESPACE/taskflow-api:$VERSION
    docker push $NAMESPACE/taskflow-web:$VERSION

Note that '$NAMESPACE' must be a namespace you can write to. The default
'taskflow' is a local placeholder and will be rejected by Docker Hub; set
REGISTRY_NAMESPACE in .env to your own username first.${RESET}
NOTE
  exit 0
fi

step "Push requested"
printf '%sAbout to publish these images publicly:%s\n' "$YELLOW" "$RESET"
printf '  %s/taskflow-api:%s\n  %s/taskflow-web:%s\n' "$NAMESPACE" "$VERSION" "$NAMESPACE" "$VERSION"
printf '%sThis is hard to undo -- tags can be deleted but anything already pulled stays pulled.%s\n' "$DIM" "$RESET"
read -r -p "Type the version ($VERSION) to confirm: " confirm
if [[ "$confirm" != "$VERSION" ]]; then
  echo "Aborted; nothing was pushed."
  exit 1
fi

for entry in "${IMAGES[@]}"; do
  name=${entry%%:*}
  docker push "$NAMESPACE/$name:$VERSION"
done

printf '\n%sPushed %s/taskflow-api:%s and %s/taskflow-web:%s%s\n' \
  "$GREEN$BOLD" "$NAMESPACE" "$VERSION" "$NAMESPACE" "$VERSION" "$RESET"
printf '%s"latest" was tagged locally but deliberately not pushed.%s\n' "$DIM" "$RESET"
