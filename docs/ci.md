# CI/CD

The image is built by Jenkins from the [`Jenkinsfile`](../Jenkinsfile) and published to Docker Hub as
[`ruepp/doctr-api`](https://hub.docker.com/r/ruepp/doctr-api).

## Pipeline

```
Prepare ──► Build ┬─ amd64 (agent 'docker')         ─┬─► Manifest
                  └─ arm64 (agent 'oracle_docker')  ─┘
```

| Stage | What happens |
| --- | --- |
| **Prepare** | `scripts/resolve_version.sh` decides which docTR release to build (once, for all agents) |
| **Build** (parallel) | Each architecture is built **natively** on its own agent: test suite → JUnit report → image pushed **by digest, untagged** |
| **Manifest** | `scripts/docker_manifest.sh` joins both digests into one multi-arch manifest and tags it |

Both architectures must succeed; otherwise nothing is tagged. A failed build is retried once after
60 s (Jenkins restarts, registry hiccups). The result is sent to Discord.

## Release monitoring

The `URLTrigger` in the `Jenkinsfile` polls every 30 minutes:

| Watched URL | Field | Effect |
| --- | --- | --- |
| `https://api.github.com/repos/mindee/doctr/releases/latest` | `$.tag_name` | New docTR release → built and published as `<tag>` + `latest` |
| `https://hub.docker.com/v2/repositories/library/python/tags/3.12-slim` | `$.digest` | New base image → current release rebuilt, tag overwritten |

Pre-releases and drafts are ignored, because GitHub's `releases/latest` never returns them.

Polling runs on an agent labelled `urltrigger`.

## Tags

Determined by `scripts/docker_tags.sh`:

| Branch | Repository | Tags |
| --- | --- | --- |
| `main` / `master` | `ruepp/doctr-api` | `<release>` (e.g. `v1.1.0`), plus `latest` if it is the newest release |
| any other | `ruepp/doctr-api-test` | `<branch>-<release>`, e.g. `feature-x-v1.1.0` |

## Building a specific release

*Build with Parameters* → `DOCTR_VERSION_OVERRIDE` = `v1.0.1` (any tag of `mindee/doctr`).

The tag is validated against GitHub before anything is built. `latest` is only set when the override
equals the newest release, so rebuilding an old release never moves `latest` backwards.

## Jenkins requirements

| What | Where |
| --- | --- |
| Agent label `docker` | amd64 agent with Docker + buildx, `git`, `curl` |
| Agent label `oracle_docker` | arm64 agent with Docker + buildx |
| Agent label `urltrigger` | runs the URLTrigger polling |
| `DOCKER_USERNAME` | environment variable on the agents |
| `DOCKER_API_PASSWORD` | Jenkins *secret text* credential (Docker Hub access token) |
| `DISCORD_WEBHOOK` | environment variable / global property for notifications |
| Plugins | Pipeline, GitHub, URLTrigger, JUnit, Workspace Cleanup, Discord Notifier |

`scripts/docker_platforms.sh` checks that each agent really has the architecture its label promises
and fails otherwise.

## Scripts

| Script | Purpose |
| --- | --- |
| `resolve_version.sh` | Latest release from GitHub, or `DOCTR_VERSION_OVERRIDE`, validated; prints `<tag> <is-latest>` |
| `start.sh` | Build workflow of one architecture: init, tests, build + push by digest |
| `test.sh` | Builds the `test-results` target and exports the JUnit reports |
| `docker_initialize.sh` | Docker login, buildx builder, QEMU only if foreign platforms are requested |
| `docker_platforms.sh` | Resolves `DOCKER_PLATFORMS` (`host` = native only) |
| `docker_tags.sh` | Repository and tags (see above) |
| `docker_manifest.sh` | Joins the per-architecture digests into the tagged manifest list |
| `docker_cleanup.sh` | Prunes build cache and builder after each build |

### Running the CI build by hand

```bash
export IMAGE_FULLNAME=ruepp/doctr-api DOCKER_USERNAME=... DOCKER_API_PASSWORD=...
read -r DOCTR_VERSION DOCTR_IS_LATEST < <(./scripts/resolve_version.sh)
export DOCTR_VERSION DOCTR_IS_LATEST BRANCH_NAME=my-test   # anything but main → ruepp/doctr-api-test
./scripts/start.sh           # this machine's architecture, pushed by digest
MANIFEST_ARCHS=amd64 ./scripts/docker_manifest.sh
```
