# Workflows

Eleven files: ten workflows plus the Dependabot configuration. The action they
publish, `action.yml`, lives at the repository root because GitHub requires it
there.

## What runs when

| Workflow | Trigger | What it does |
|---|---|---|
| [`ci.yml`](ci.yml) | push to `main`/`develop`, every PR, manual | Validates the Compose files, lints scripts/Dockerfiles/workflows, checks the API on Node 20 and 22, builds and scans both images, then runs the whole stack end to end. On a green `main` push it publishes `edge` images to GHCR. |
| [`codeql.yml`](codeql.yml) | push, PR, weekly, manual | CodeQL over the JavaScript **and** over the workflow files themselves. |
| [`copilot-code-review.yml`](copilot-code-review.yml) | PR opened / reopened / ready for review, manual | Asks GitHub Copilot to review the pull request. Warns instead of failing when Copilot code review is not available. |
| [`dependabot-auto-merge.yml`](dependabot-auto-merge.yml) | Dependabot PRs | Approves patch and minor updates and queues them for auto-merge once CI is green. Labels majors for a human. |
| [`dependency-updates.yml`](dependency-updates.yml) | Tuesdays 06:15 UTC, manual | Rolls `api/package-lock.json` forward, verifies it still installs, and opens one pull request. |
| [`docker-publish.yml`](docker-publish.yml) | manual, or called by `release.yml` | Builds both images for amd64 + arm64 and pushes them to Docker Hub. |
| [`github-packages.yml`](github-packages.yml) | manual, or called by `ci.yml` / `release.yml` | The same, to GHCR, authenticated with the job's own token. |
| [`release.yml`](release.yml) | push of a `v*` tag, manual | Verifies the stack, creates the tag, publishes to both registries, then cuts the GitHub release with a deployment bundle attached. |
| [`deploy-production.yml`](deploy-production.yml) | manual, or called | Verifies the released images exist, renders the production Compose file, waits for approval on the `production` environment, deploys, health-checks. |
| [`publish-marketplace.yml`](publish-marketplace.yml) | release published, manual | Validates `action.yml` against every Marketplace requirement, runs the action for real, moves the `v1` tag, and prints the link for the one manual step GitHub has no API for. |
| [`../dependabot.yml`](../dependabot.yml) | weekly | Watches npm, three Docker contexts and the workflow files. |

The dependency graph between them:

```
  push / PR ───► ci.yml ──(main only, after green)──► github-packages.yml  (edge)

  git push v1.2.0 ──► release.yml ──► docker-publish.yml    (Docker Hub)
                            │      └─► github-packages.yml  (GHCR)
                            └────────► GitHub release + deploy bundle

  manual ──► deploy-production.yml ──► [production environment gate] ──► deploy

  manual ──► publish-marketplace.yml ──► validate ► run the action ► move v1
```

## Setup

### 1. Docker Hub secrets — required for `docker-publish.yml`

Settings → Secrets and variables → Actions → **Secrets**:

| Secret | Value |
|---|---|
| `DOCKERHUB_USERNAME` | Your Docker Hub account name. |
| `DOCKERHUB_TOKEN` | A Docker Hub access token with **Read & Write** scope (Docker Hub → Account settings → Personal access tokens). `DOCKERHUB_PASSWORD` is accepted as a fallback. |

And under **Variables**, optionally:

| Variable | Why |
|---|---|
| `DOCKERHUB_NAMESPACE` | The namespace to publish under; defaults to `DOCKERHUB_USERNAME`. Setting it as a variable keeps the image name readable in the logs — a secret is printed as `***`. |

Nothing else needs a secret. GHCR, releases, Copilot and Dependabot all use the
job's built-in `GITHUB_TOKEN`.

### 2. Repository settings

| Setting | Where | Needed by |
|---|---|---|
| **Allow auto-merge** | Settings → General → Pull Requests | `dependabot-auto-merge.yml` — without it nothing can be queued. |
| **Allow GitHub Actions to create and approve pull requests** | Settings → Actions → General → Workflow permissions | `dependency-updates.yml`. |
| Code scanning set to **Advanced** (or off) | Settings → Code security | `codeql.yml`. Default setup and an advanced workflow are mutually exclusive; with Default setup on, this workflow fails. |
| A `production` **environment** with a required reviewer | Settings → Environments | `deploy-production.yml`. Without it the deploy runs unattended. |
| A ruleset on `main` requiring the **`CI result`** check | Settings → Rules | Gives auto-merge something to wait for. Without a required check, auto-merge merges immediately. |

### 3. Optional secrets and variables

| Name | Kind | Effect |
|---|---|---|
| `COPILOT_REVIEW_TOKEN` | secret | Used instead of `GITHUB_TOKEN` when requesting a Copilot review. |
| `DEPENDENCY_UPDATES_TOKEN` | secret | Makes CI run on the pull request `dependency-updates.yml` opens. Pushes made with the default token do not start workflows. |
| `PRODUCTION_URL` | variable | Enables the post-deploy health check. |
| `DEPLOY_REGISTRY` | variable | `ghcr` (default) or `dockerhub`. |

## Cutting a release

```bash
git tag v1.1.0 && git push origin v1.1.0
```

Or run **Release** from the Actions tab with `1.1.0` and let it create the tag.
Either way: the stack is brought up and exercised, both registries are
published, and the release is created with a deployment bundle attached.
Deploying stays a separate, approved step.

## Publishing the action to the Marketplace

Run **Publish Marketplace**. It validates `action.yml`, runs the action for
real against this stack, moves `v1`, and finishes with a link to the release
edit page. Tick **Publish this Action to the GitHub Marketplace** there — that
single box is the only part of the process GitHub exposes no API for, and it is
only needed the first time.

## Changing a workflow

`ci.yml` lints the workflows with [actionlint](https://github.com/rhysd/actionlint),
which also runs shellcheck over every `run:` block. To catch problems before
pushing:

```bash
docker run --rm -v "$PWD:/repo" --workdir /repo rhysd/actionlint:latest -color
```
