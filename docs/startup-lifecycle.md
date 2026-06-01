# Startup & Configuration Lifecycle

## Container Startup Flow

```
Docker run / Kubernetes pod start
         │
         ▼
    tini (PID 1 signal handling)
         │
         ▼
   entrypoint.sh (runs as root)
         │
         ├─(1)─ Collect all JAVA_OPTS_* env vars → append to JAVA_OPTS
         │
         ├─(2)─ Resolve config source:
         │        ├─ JENKINS_ENV_CONFIG_YAML → write to /dev/shm/jenkins-config.yml, unset var
         │        └─ JENKINS_ENV_CONFIG_YML_URL → fetchconfig.py → /dev/shm/jenkins-config.yml
         │
         ├─(3)─ If URL mode: start watch-config.sh in background (polling loop)
         │
         ├─(4)─ Install additional plugins (JENKINS_ENV_PLUGINS)
         │
         ├─(5)─ Resolve JENKINS_IP_FOR_SLAVES (JENKINS_ENV_HOST_IP or eval JENKINS_ENV_HOST_IP_CMD)
         │
         ├─(6)─ chown /jenkins-workspace-home and $JENKINS_HOME to jenkins user
         │
         ├─(7)─ Add jenkins user to docker group (if docker.sock mounted)
         │
         └─(8)─ exec: gosu jenkins /usr/local/bin/jenkins.sh
                   │
                   ▼
             Official Jenkins startup
                   │
                   ▼
             Init scripts execute (init.groovy.d/*.groovy.override)
                   │
                   ▼
             JenkinsConfigLoader.groovy (the main orchestrator)
                   │
                   ├─ Generate admin API token (stored in /dev/shm/.api-token)
                   │
                   ├─ Load /dev/shm/jenkins-config.yml
                   │
                   ├─ Apply env var substitution (${VAR} → value)
                   │
                   ├─ Route to correct mode:
                   │     ├─ JENKINS_ENV_CONFIG_MODE=jcasc → ConfigurationAsCode plugin
                   │     └─ Default → Run config handlers sequentially
                   │
                   └─ Execute each handler via:
                         evaluate(new File("config-handlers/${Handler}Config.groovy")).setup(config)
```

## Config Handler Execution Order

The order matters because some handlers depend on others being configured first:

| # | Handler | Config Key | Purpose |
|---|---------|-----------|---------|
| 1 | ProxyConfig | `proxy` | HTTP proxy before any external connections |
| 2 | GeneralConfig | (env vars) | Executors, workspace dir, Jenkins URL, quiet mode |
| 3 | RemoveMasterEnvVarsConfig | `remove_master_envvars` | Hide secrets from System Info page |
| 4 | EnvironmentVarsConfig | `environment` | Set global environment variables |
| 5 | ConfigurationAsCodeConfig | `configuration_as_code` | Mixed-mode JCasC snippets |
| 6 | CredsConfig | `credentials` | Create credentials (needed by subsequent handlers) |
| 7 | SecurityConfig | `security` | Auth realm, permissions, security options |
| 8 | CloudsConfig | `clouds` | Docker/ECS/Kubernetes slave clouds |
| 9 | NotifiersConfig | `notifiers` | Mail, Slack notifications |
| 10 | ToolsConfig | `tools` | JDK, Maven, Ant, Gradle, etc. |
| 11 | ArtifactoryConfig | `artifactory` | JFrog Artifactory servers |
| 12 | SonarQubeServersConfig | `sonar_qube_servers` | SonarQube analysis servers |
| 13 | JiraConfig | `jira` | Jira integration plugin |
| 14 | JiraStepsConfig | `jiraSteps` | Jira pipeline steps |
| 15 | CheckmarxConfig | `checkmarx` | Checkmarx security scans |
| 16 | GitlabConfig | `gitlab` | GitLab plugin configuration |
| 17 | PipelineLibrariesConfig | `pipeline_libraries` | Shared pipeline libraries |
| 18 | SeedJobsConfig | `seed_jobs` | Seed job creation and triggers |
| 19 | JobDSLScriptsConfig | `job_dsl_scripts` | Inline JobDSL scriptlets |
| 20 | ScriptApprovalConfig | `script_approval` | Script security whitelist |
| 21 | CustomConfig | `customConfig` | User-provided custom handler |

## Configuration Watch Loop

When `JENKINS_ENV_CONFIG_YML_URL` is set (unless `JENKINS_ENV_CONFIG_YML_URL_DISABLE_WATCH=true`):

```
watch-config.sh (runs in background via nohup)
         │
         ▼
   ┌─► fetch_config()
   │       │
   │       ├─ fetchconfig.py --source <URL> --out /dev/shm/.cache/
   │       │     (fetches from file/s3/http, deep-merges multiple sources)
   │       │
   │       ├─ processconfig.py --source ... --env-dirs ...
   │       │     (runs inside envconsul-wrapper.sh for Consul/Vault env vars)
   │       │     (substitutes ${VAR} with environment variable values)
   │       │
   │       └─ Compare MD5 checksum with previous
   │             ├─ Changed → copy to CONFIG_FILE_LOCATION, return exit 30
   │             └─ Unchanged → clean up, return exit 0
   │
   │   if exit 30 (changed):
   │       └─ update-config.sh
   │             └─ java -jar jenkins-cli.jar groovy = < JenkinsConfigLoader.groovy
   │                   (re-applies all config handlers to running Jenkins)
   │
   └─ sleep POLLING_INTERVAL (default 30s)
```

## Environment Variable Substitution

The config YAML supports `${VAR_NAME}` syntax. Processing happens in two stages:

1. **processconfig.py** (pre-Jenkins): Replaces `${VAR}` with env var values using `os.path.expandvars()`. Supports `\${VAR}` escaping for literal `$` characters.

2. **JenkinsConfigLoader.groovy** (init script): Additional pass using `SimpleTemplateEngine` for any vars not resolved at the Python stage.

### Environment Variable Data Sources

| Source | Mechanism | Use Case |
|--------|-----------|----------|
| Native env vars | Docker `-e` / Kubernetes `env:` | Simple secrets |
| Files | `ENVVARS_DIRS=/path1,/path2` | K8s Secret volumes |
| Consul | `ENVCONSUL_CONSUL_PREFIX` + `CONSUL_ADDR` | Dynamic KV config |
| Vault | `ENVCONSUL_VAULT_PREFIX` + `VAULT_ADDR` | Secret management |

File-based env vars produce names as `<FOLDER_NAME>_<FILE_NAME>` uppercased and sanitized.

## Key Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `JENKINS_ENV_ADMIN_USER` | (required) | Admin username for Jenkins |
| `JENKINS_ENV_CONFIG_YAML` | - | Config as inline YAML string |
| `JENKINS_ENV_CONFIG_YML_URL` | - | Config source URL(s) (file/s3/http) |
| `JENKINS_ENV_CONFIG_YML_URL_DISABLE_WATCH` | false | Disable config watching |
| `JENKINS_ENV_CONFIG_YML_URL_POLLING` | 30 | Watch polling interval (seconds) |
| `JENKINS_ENV_CONFIG_MODE` | - | Set to `jcasc` for JCasC mode |
| `JENKINS_ENV_HOST_IP` | - | Static IP for JNLP slaves |
| `JENKINS_ENV_HOST_IP_CMD` | - | Command to fetch IP dynamically |
| `JENKINS_ENV_JENKINS_URL` | - | Override Jenkins root URL |
| `JENKINS_ENV_ADMIN_ADDRESS` | - | Admin email address |
| `JENKINS_ENV_PLUGINS` | - | Additional plugins to install at startup |
| `JENKINS_ENV_QUIET_STARTUP_PERIOD` | - | Seconds to start in quiet mode |
| `JENKINS_ENV_EXECUTERS` | 0 | Number of master executors |
| `JENKINS_ENV_CHANGE_WORKSPACE_DIR` | true | Use /jenkins-workspace-home for workspaces |
| `CONFIG_FILE_LOCATION` | /dev/shm/jenkins-config.yml | Where processed config is written |
| `TOKEN_FILE_LOCATION` | /dev/shm/.api-token | Admin API token location |
| `CONFIG_CACHE_DIR` | /dev/shm/.jenkins-config-cache | Cache for watch loop |

## Key Files in /dev/shm

Using tmpfs for config files ensures:
- Secrets never touch persistent disk
- Fast read/write for frequent polling
- Automatic cleanup on container restart
