# Deployment & Build

## Docker Image Variants

Three base variants are built for each release:

| Variant | Base Image | FROM_TAG |
|---------|-----------|----------|
| Alpine | `jenkins/jenkins:2.555.3-alpine` | `${LTS_VERSION}-alpine` |
| Debian | `jenkins/jenkins:2.555.3` | `${LTS_VERSION}` |
| JDK21 | `jenkins/jenkins:2.555.3-jdk21` | `${LTS_VERSION}-jdk21` |

> The default `FROM_TAG` in the `Dockerfile` is `2.555.3-jdk21`. The Makefile and `publish.sh` build all three variants.

## Versioning

- **Git tags**: `v${LTS_VERSION}-${INCREMENT}` (e.g., `v2.555.1-306`)
- **Docker tags per release**: `2.555.1-306`, `2.555.1`, `lts`, plus `-debian` and `-jdk21` suffixes
- **Master branch**: tagged as `latest` / `alpine` / `debian` / `jdk21`

## Registries

| Registry | Image |
|----------|-------|
| Docker Hub | `gfnord/my-bloody-jenkins:<tag>` |
| GitHub CR | `ghcr.io/gfnord/my-bloody-jenkins:<tag>` |

## Building Locally

```bash
# Build all variants
make build-all

# Build a single variant
make build-alpine
make build-debian
make build-jdk21

# With proxy support (uses http_proxy/https_proxy env vars)
make build-alpine
```

## Publishing

The `publish.sh` script handles multi-variant builds and pushes:

```bash
# Publish a release (from tag)
./publish.sh v2.555.1-306

# Publish latest (from master)
./publish.sh latest
```

For a versioned release, `publish.sh` builds and pushes **9 images**:
- `$tag`, `$short_tag`, `lts` (Alpine)
- `$tag-debian`, `$short_tag-debian`, `lts-debian`
- `$tag-jdk21`, `$short_tag-jdk21`, `lts-jdk21`

## Plugin Management

### Bundled Plugins (`plugins.txt`)

213+ plugins are pinned in `plugins.txt` and installed at build time via `jenkins-plugin-cli`. Key plugin categories:

- **Cloud**: docker-plugin, kubernetes
- **SCM**: git, git-client, subversion, gitlab-plugin, github-branch-source
- **Pipeline**: workflow-aggregator, pipeline-stage-view, pipeline-model-definition
- **Security**: ldap, active-directory, saml, google-login, github-oauth
- **Integration**: artifactory, sonar, jira, slack, checkmarx
- **UI**: blueocean, configuration-as-code

### Updating Plugins

```bash
# Auto-update all plugins to latest from Jenkins Update Center
make update-plugins
```

`get-latest-plugins.py` fetches the latest versions from `https://updates.jenkins.io/stable/update-center.json` and updates `plugins.txt`. Plugins listed in `.ignored-update-plugins` are excluded from auto-update.

### Adding Plugins at Runtime

```bash
docker run -e JENKINS_ENV_PLUGINS=plugin1:1.0,plugin2:2.0 ...
```

Plugins are installed before Jenkins starts, but this is not recommended for production.

## Docker Image Contents

Installed beyond the base Jenkins image:

| Component | Version | Purpose |
|-----------|---------|---------|
| Python 3 | System | Config processing scripts |
| pip packages | PyYAML, six, requests | YAML processing |
| envconsul | 0.13.2 | Consul/Vault env var injection |
| gosu | 1.17 | Drop root privileges to jenkins user |
| tini | From base | PID 1 signal handling |
| Init scripts | Custom | JenkinsConfigLoader + config handlers |

## Deployment Patterns

### Basic Docker Run

```bash
docker run -d \
  -p 8080:8080 -p 50000:50000 \
  -e JENKINS_ENV_ADMIN_USER=admin \
  -e JENKINS_ENV_CONFIG_YAML="$(cat config.yml)" \
  -v jenkins-home:/var/jenkins_home \
  gfnord/my-bloody-jenkins:lts
```

### Config from File

```bash
docker run -d \
  -e JENKINS_ENV_ADMIN_USER=admin \
  -e JENKINS_ENV_CONFIG_YML_URL=file:///config/config.yml \
  -v /path/to/config:/config:ro \
  -v jenkins-home:/var/jenkins_home \
  gfnord/my-bloody-jenkins:lts
```

### Config from Multiple Sources (Deep Merge)

```bash
docker run -d \
  -e JENKINS_ENV_ADMIN_USER=admin \
  -e JENKINS_ENV_CONFIG_YML_URL="file:///config/base.yml,file:///config/override.yml" \
  -v /path/to/config:/config:ro \
  gfnord/my-bloody-jenkins:lts
```

### With Kubernetes Secrets

```bash
# Mount secrets as files
-e ENVVARS_DIRS=/var/secrets/ \
-v my-secrets:/var/secrets:ro

# Config references env vars from those files
# security:
#   managerPassword: '${MY_SECRET_PASSWORD}'
```

### Kubernetes via Helm

The upstream maintainer's Helm chart works with this fork. Point `image.repository` at `gfnord/my-bloody-jenkins`:

```bash
helm repo add odavid https://odavid.github.io/k8s-helm-charts
helm install my-jenkins odavid/my-bloody-jenkins \
  --set image.repository=gfnord/my-bloody-jenkins \
  -f values.yml
```

Helm chart source: https://github.com/odavid/k8s-helm-charts/tree/master/charts/my-bloody-jenkins

### JCasC Mode

```bash
docker run -d \
  -e JENKINS_ENV_ADMIN_USER=admin \
  -e JENKINS_ENV_CONFIG_MODE=jcasc \
  -e JENKINS_ENV_CONFIG_YAML="$(cat jcasc-config.yml)" \
  gfnord/my-bloody-jenkins:lts
```

### Behind Load Balancer

```bash
-e JENKINS_ENV_HOST_IP_CMD='curl http://169.254.169.254/latest/meta-data/local-ipv4'
-e JENKINS_HTTP_PORT_FOR_SLAVES=8080
```

## Make Targets

| Target | Description |
|--------|-------------|
| `default` | `test-all` |
| `build-all` | Build alpine + debian + jdk21 |
| `test-all` | Test alpine + debian + jdk21 |
| `test-alpine` | Build and test alpine |
| `test-debian` | Build and test debian |
| `test-jdk21` | Build and test jdk21 |
| `update-plugins` | Auto-update plugins from UC |
| `release` | Create new version git tag |
