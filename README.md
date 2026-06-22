# My Bloody Jenkins - An opinionated Jenkins Docker Image

[![Docker Pulls](https://img.shields.io/docker/pulls/gfnord/my-bloody-jenkins.svg)](https://hub.docker.com/r/gfnord/my-bloody-jenkins/)
[![Changelog](https://img.shields.io/github/v/tag/gfnord/my-bloody-jenkins?label=changelog)](https://github.com/gfnord/my-bloody-jenkins/blob/master/CHANGELOG.md)

> **Fork notice**: This is the `gfnord` fork of [odavid/my-bloody-jenkins](https://github.com/odavid/my-bloody-jenkins), pinned to Jenkins LTS `2.555.3` on JDK 21. It vendors its own Helm chart. There is no CI; the image and chart are built and published manually.

## What's in the Box?

A re-distribution of the [official LTS Jenkins Docker image](https://hub.docker.com/r/jenkins/jenkins/) bundled with a curated plugin set and the ability to configure Jenkins from a **single YAML source of truth**.

- **Configuration as YAML**: security realm, clouds, credentials, tools, notifiers, pipeline libraries, seed jobs, script approvals, JCasC snippets — all from one file.
- **Live reload**: configuration changes are watched and re-applied without restarting Jenkins.
- **Multiple data sources**: file, HTTP, environment variable, Kubernetes ConfigMap, Kubernetes Secret. Deep-merged top to bottom.
- **Secret substitution**: `${VAR}` expansion from env, files, Consul, or Vault (via envconsul).
- **Curated plugins**: 72 plugins covering Kubernetes + Docker clouds, Git, credentials, Slack, JCasC, pipeline core. See [`plugins.txt`](./plugins.txt).
- **Custom config hook**: drop a `CustomConfig.groovy` into the image for handlers this fork doesn't ship.

Detailed design and configuration reference live in [`docs/`](./docs):

| Doc | Covers |
|---|---|
| [docs/architecture.md](./docs/architecture.md) | Project layout, design decisions, technology stack |
| [docs/deployment.md](./docs/deployment.md) | Image variants, build, publish, plugin management, deployment patterns |
| [docs/config-handlers.md](./docs/config-handlers.md) | Every YAML section, its handler, and accepted keys |
| [docs/startup-lifecycle.md](./docs/startup-lifecycle.md) | Container startup flow, env vars, config watch loop |
| [docs/testing.md](./docs/testing.md) | How tests are structured and run |

## Build the Image

```sh
podman login -u gfnord docker.io
podman build -t gfnord/my-bloody-jenkins:2.555.3 .
podman push gfnord/my-bloody-jenkins:2.555.3
```

Ensure `unqualified-search-registries = ["docker.io"]` is set in `/etc/containers/registries.conf`. For Make targets (`build-all`, `test-all`, `release`), see [docs/deployment.md](./docs/deployment.md#make-targets).

## Deploy on Kubernetes (Helm)

This repo vendors its chart under [`chart/`](./chart). To publish it as an OCI artifact to GHCR, package and push manually:

```sh
helm package chart/ --destination packaged/
helm push packaged/my-bloody-jenkins-*.tgz oci://ghcr.io/gfnord/charts
```

### From GHCR (recommended)

```sh
echo "$GITHUB_TOKEN" | helm registry login ghcr.io -u <github-user> --password-stdin

helm install jenkins oci://ghcr.io/gfnord/charts/my-bloody-jenkins \
  --version 1.0.0 \
  -f values.yaml
```

### From a local clone (for testing)

```sh
helm install jenkins ./chart -f values.yaml
```

### Upgrade

```sh
helm upgrade jenkins oci://ghcr.io/gfnord/charts/my-bloody-jenkins \
  --version 1.0.0 \
  -f values.yaml
```

Chart defaults point at `gfnord/my-bloody-jenkins:2.555.3`. Override `image.tag` to pin a different build. See [`chart/values.yaml`](./chart/values.yaml) for the full values schema.

## Releases

Docker images are pushed to [Docker Hub](https://hub.docker.com/r/gfnord/my-bloody-jenkins/) and [GHCR](https://github.com/gfnord/my-bloody-jenkins/pkgs/container/my-bloody-jenkins).

Each release is a git tag `v$LTS_VERSION-$INCREMENT` (e.g. `v2.555.3-306`). For each tag, the following image tags are produced:

- `2.555.3-306` — exact release
- `2.555.3` — latest release for that LTS line
- `lts` — latest LTS release

Per-variant suffixes: `-debian`, `-jdk21`. Master commits are tagged `latest`, `debian`, `jdk21`.

```bash
docker pull gfnord/my-bloody-jenkins:lts             # latest LTS (alpine)
docker pull gfnord/my-bloody-jenkins:lts-jdk21        # latest LTS (jdk21)
docker pull gfnord/my-bloody-jenkins:2.555.3          # latest 2.555.3
docker pull gfnord/my-bloody-jenkins:v2.555.3-306     # pinned release
docker pull ghcr.io/gfnord/my-bloody-jenkins:lts      # same tags via GHCR
```

## Examples

- [`examples/docker/`](./examples/docker) — Docker-plugin cloud with seed job
- [`examples/kubernetes/`](./examples/kubernetes) — Kubernetes cloud via Minikube with seed job
- [`demo/`](./demo) — step-by-step walkthrough

## Fork Differences vs Upstream

This fork tracks `odavid/my-bloody-jenkins` with the following intentional divergences:

- **Jenkins LTS**: pinned to `2.555.3` (JDK 21)
- **Plugins trimmed**: 213 → 72, scoped to Kubernetes + Git + Docker + Slack + JCasC. Removed: BlueOcean, unused SCM integrations, unused auth realms, unused build tools, unused reporting, unused UI extras.
- **AWS removed**: no Amazon ECS cloud, no AWS credentials, no `aws-java-sdk-*` plugins, no `boto3`/`awscli` in the image, no `s3://` config source.
- **Helm chart vendored**: `chart/` ships in this repo; push it to `ghcr.io/gfnord/charts/my-bloody-jenkins` manually when cutting a release. No `helm repo add odavid ...` required.
- **No CI**: image and chart are built and published manually from a local checkout (see `publish.sh`, `Makefile`, and [docs/deployment.md](./docs/deployment.md)).

See [`CHANGELOG.md`](./CHANGELOG.md) for the full history.
