# Architecture Overview

## What is My Bloody Jenkins?

An opinionated Docker image for Jenkins LTS that bundles popular plugins and enables full Jenkins configuration from a **single YAML file**. Supports live configuration reloading without restarts, multiple config data sources, and production deployment patterns.

> **Fork notice**: This is the `gfnord` fork of [odavid/my-bloody-jenkins](https://github.com/odavid/my-bloody-jenkins). It tracks upstream and republishes images as `gfnord/my-bloody-jenkins` on Docker Hub and GHCR. The fork is pinned to Jenkins LTS `2.555.1` on JDK 21.

**Base image**: `jenkins/jenkins:${FROM_TAG}` (Alpine, Debian, or JDK21 variants)
**Current LTS pin**: `2.555.1` (see `LTS_VERSION.txt`)
**Latest tagged release**: `v2.426.3-305` (the `2.555.1` line is in-development; next release will be `2.555.1-306`)

## Project Structure

```
my-bloody-jenkins/
├── Dockerfile                 # Image definition (builds on jenkins/jenkins LTS)
├── Makefile                   # Build/test/release targets
├── publish.sh                 # Multi-variant Docker image publishing
├── LTS_VERSION.txt            # Current Jenkins LTS version pin
├── plugins.txt                # Pinned plugin versions (213 plugins)
├── plugins.txt.orig           # Original plugin list (before auto-update)
├── get-latest-plugins.py      # Auto-update plugin versions from Jenkins UC
├── .ignored-update-plugins    # Plugins excluded from auto-update
│
├── bin/                       # Shell/Python scripts for entrypoint & config
│   ├── entrypoint.sh          # Container entrypoint (tini -> gosu jenkins)
│   ├── fetchconfig.py         # Fetch YAML from file/http and deep-merge
│   ├── processconfig.py      # Env var substitution in YAML config
│   ├── watch-config.sh        # Poll for config changes and hot-reload
│   ├── update-config.sh       # Trigger Jenkins reconfiguration via CLI
│   └── envconsul-wrapper.sh   # Wrap commands with envconsul for Consul/Vault
│
├── init-scripts/              # Jenkins init.groovy.d scripts (run at startup)
│   └── JenkinsConfigLoader.groovy  # Main orchestrator for all config handlers
│
├── config-handlers/           # Groovy scripts handling each YAML config section
│   ├── GeneralConfig.groovy          # Executors, workspace dir, quiet mode, URL
│   ├── ProxyConfig.groovy            # HTTP proxy settings
│   ├── SecurityConfig.groovy         # Auth realms (LDAP/AD/SAML/OAuth/DB)
│   ├── CredsConfig.groovy            # Credentials (text/file/userpass/ssh/cert)
│   ├── CloudsConfig.groovy           # Cloud providers (Docker/Kubernetes)
│   ├── EnvironmentVarsConfig.groovy  # Global environment variables
│   ├── RemoveMasterEnvVarsConfig.groovy  # Hide secrets from System Info
│   ├── ToolsConfig.groovy            # JDK/Ant/Maven/Gradle/SonarQube/Golang
│   ├── NotifiersConfig.groovy        # Mail/Slack notifications
│   ├── PipelineLibrariesConfig.groovy  # Shared pipeline libraries
│   ├── SeedJobsConfig.groovy         # Seed job creation & triggers
│   ├── JobDSLScriptsConfig.groovy    # Inline JobDSL scriptlets
│   ├── ScriptApprovalConfig.groovy   # Script security whitelisting
│   ├── ConfigurationAsCodeConfig.groovy  # Mixed-mode JCasC support
│   ├── ArtifactoryConfig.groovy      # JFrog Artifactory plugin
│   ├── SonarQubeServersConfig.groovy # SonarQube analysis
│   ├── JiraConfig.groovy             # Jira integration plugin
│   ├── JiraStepsConfig.groovy        # Jira pipeline steps
│   ├── CheckmarxConfig.groovy        # Checkmarx security scans
│   └── GitlabConfig.groovy           # GitLab integration
│
├── tests/                     # Integration tests (BATS + Groovy)
│   ├── config-handlers-tests.bats           # Tests all 18 config handlers
│   ├── config-deep-merge-tests.bats          # Tests multi-file deep merge
│   ├── config-envvars-from-files.bats        # Tests ENVVARS_DIRS feature
│   ├── envconsule-tests.bats                 # Tests Consul/Vault integration
│   ├── tests_helpers.bash                    # Shared test utilities
│   ├── run-jenkins-groovy.sh                 # Groovy execution via Jenkins CLI
│   ├── docker-compose-simple.yml              # Test Jenkins container
│   ├── docker-compose-consul.yml              # Consul + Vault test services
│   ├── data/config-fixtures/                  # YAML config test fixtures
│   └── groovy/                                # Groovy assertion scripts
│       ├── config-handlers/                   # Per-handler validation scripts
│       ├── envconsul/                        # Consul/Vault assertion scripts
│       ├── deep-merge/                       # Deep-merge assertion scripts
│       └── envvars/                          # File-based envvar assertion scripts
│
├── demo/                      # Interactive demos
│   ├── step-by-step/          # Incremental config tutorial with LDAP
│   │   ├── docker-compose.yml
│   │   ├── config-templates/  # 5 incremental config steps
│   │   └── assets/apps/       # Sample Node.js and Java apps
│   └── jcasc-plugin/          # Pure JCasC configuration mode demo
│       └── docker-compose.yml
│
├── examples/                  # Production-like examples
│   ├── docker/                # Docker cloud + seed job example
│   ├── kubernetes/            # Minikube Kubernetes cloud example
│   └── jobs/                  # Sample seed job and JobDSL scripts
│
└── slides/                    # Presentation (PPTX)
```

## Key Design Decisions

### Single YAML Configuration
All Jenkins configuration lives in one YAML file with typed sections. Each section maps to a Groovy config handler that applies settings programmatically to the Jenkins instance.

### Dual Configuration Mode
- **Builtin handlers** (default): Custom Groovy scripts process each YAML section
- **JCasC mode** (`JENKINS_ENV_CONFIG_MODE=jcasc`): Delegates to Jenkins Configuration as Code plugin
- **Mixed mode**: Use builtin handlers with embedded `configuration_as_code:` section for unsupported plugins

### Live Configuration Reload
Configuration is fetched from URLs (file/http), watched for changes, and re-applied without restarting Jenkins via `update-config.sh` calling `jenkins-cli.jar groovy`.

### Secret Management
- Environment variable substitution: `${SECRET}` in YAML
- File-based secrets: `ENVVARS_DIRS` for Kubernetes Secret volumes
- Consul/Vault integration via `envconsul`
- Secrets are unset from env vars after processing (won't appear in System Info)

### Configuration Deep Merge
Multiple YAML sources can be specified via comma-separated URLs. Files are deep-merged top-to-bottom, enabling modular configuration with overrides.

## Technology Stack

| Component | Technology |
|-----------|-----------|
| Base | Jenkins LTS Docker image |
| Shell | Bash (entrypoint, watchers) |
| Config processing | Python 3 (fetchconfig, processconfig) |
| Config application | Groovy (Jenkins init scripts) |
| Secret fetching | HashiCorp envconsul 0.13.2 |
| Container init | tini + gosu |
| Cloud tools | PyYAML, requests |
| Testing | BATS + Jenkins CLI + Groovy assertions |
| CI/CD | GitHub Actions (3-distribution matrix) |
