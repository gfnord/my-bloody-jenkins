# Configuration Handlers Reference

Each config handler is a Groovy script at `/usr/share/jenkins/config-handlers/<Name>Config.groovy` that implements a `setup(config)` method. The handler receives its section of the YAML config and programmatically applies it to the Jenkins instance.

## Handler Pattern

```groovy
// Standard handler structure
def setup(config) {
    // 1. Validate config is present
    if (!config) return

    // 2. Get Jenkins singleton instances
    def instance = jenkins.model.Jenkins.getInstance()

    // 3. Apply configuration
    // ... modify Jenkins objects ...

    // 4. Save changes
    instance.save()
}
return this
```

## Handler Details

### GeneralConfig
**Config key**: (none - uses env vars)
**File**: `config-handlers/GeneralConfig.groovy`

Configures fundamental Jenkins instance settings from environment variables:
- `JENKINS_SLAVE_AGENT_PORT` - JNLP agent port (default 50000)
- `JENKINS_ENV_EXECUTERS` - Master executor count (default 0)
- `JENKINS_ENV_CHANGE_WORKSPACE_DIR` - Moves workspace to `/jenkins-workspace-home/workspace/${ITEM_FULLNAME}` (useful for NFS-backed JENKINS_HOME)
- `JENKINS_ENV_JENKINS_URL` - Jenkins root URL
- `JENKINS_ENV_ADMIN_ADDRESS` - Admin email
- `JENKINS_ENV_QUIET_STARTUP_PERIOD` - Starts Jenkins in quiet mode for N seconds
- Triggers `DownloadService.Downloadable.all().updateNow()` in background thread

### ProxyConfig
**Config key**: `proxy`
**File**: `config-handlers/ProxyConfig.groovy`

Sets HTTP proxy configuration:
```yaml
proxy:
  proxyHost: proxy.example.com
  port: 8080
  username: proxyuser
  password: proxypass
  noProxyHost: localhost,127.0.0.1
```

### SecurityConfig
**Config key**: `security`
**File**: `config-handlers/SecurityConfig.groovy` (largest handler)

Supports 6 authentication realms:

| Realm | Config Value | Plugin |
|-------|-------------|--------|
| Jenkins DB | `jenkins_database` | Built-in |
| LDAP | `ldap` | Built-in |
| Active Directory | `active_directory` | active-directory plugin |
| SAML | `saml` | saml plugin |
| Google OAuth | `google` | google-login plugin |
| GitHub OAuth | `github` | github-oauth plugin |

Each realm has its own set of required config properties (see README for full examples).

**Additional features**:
- Matrix-based authorization via `permissions:` section (user/group → permission ID list)
- Security options: CSRF, script security, Remember Me, SSHD (port 16022), markup formatter
- User creation for Jenkins DB realm (`users:` list)
- Admin user injected from `JENKINS_ENV_ADMIN_USER`

### CredsConfig
**Config key**: `credentials`
**File**: `config-handlers/CredsConfig.groovy`

Creates credentials in the global domain. Each top-level key is the credential ID.

**Built-in types**:
- `text` - Simple secret string
- `file` - File credential (base64-encoded content + filename)
- `aws` - AWS access key + secret key
- `userpass` - Username/password pair
- `sshkey` - SSH private key (PEM text, base64, or fileOnMaster path)
- `cert` - PKCS12 certificate (base64 or fileOnMaster path)
- `gitlab-api-token` - GitLab API token

**Dynamic credentials**: If `type` is not a built-in name, the handler attempts to:
1. Use it as a fully-qualified class name (`org.jenkinsci.plugins.p4.credentials.P4TicketImpl`)
2. Search all credential descriptors for a case-insensitive name match (`usernamePassword` → `UsernamePasswordCredentialsImpl`)

Uses `DescribableModel` for instantiation, requiring `@DataBoundConstructor` / `@DataBoundSetter` compliance.

### CloudsConfig
**Config key**: `clouds`
**File**: `config-handlers/CloudsConfig.groovy`

Configures agent cloud providers. Each top-level key is the cloud name.

**Docker cloud** (`type: docker`):
- Templates with JNLP slave images, labels, volume mounts, env vars
- Pull strategies: `PULL_LATEST` (default), `PULL_ALWAYS`, `PULL_NEVER`
- Instance cap, JVM args, node usage mode

**Amazon ECS** (`type: ecs`):
- Credentials, region, cluster ARN
- Fargate support (subnets, security groups, assign public IP, execution role)
- Task placement strategies, task roles
- Memory/CPU reservations, volumes, environment, tags

**Kubernetes** (`type: kubernetes`):
- Server URL, namespace, direct connection, WebSocket support
- Pod templates with labels, resources (requests/limits), volumes
- Node selectors, runAsUser, supplementalGroups, annotations
- Custom YAML merge into pod manifest
- Idle retention, connect timeout, max requests per host

All cloud types support `JENKINS_IP_FOR_SLAVES` injection for proper JNLP routing behind load balancers.

### EnvironmentVarsConfig
**Config key**: `environment`
**File**: `config-handlers/EnvironmentVarsConfig.groovy`

Sets global environment variables as key-value pairs on the Jenkins instance. Variable names must be valid env var names.

### RemoveMasterEnvVarsConfig
**Config key**: `remove_master_envvars`
**File**: `config-handlers/RemoveMasterEnvVarsConfig.groovy`

Accepts a list of regex patterns. Any environment variable matching a pattern is hidden from the Jenkins System Information page. Essential for preventing secret leakage.

### ToolsConfig
**Config key**: `tools`
**File**: `config-handlers/ToolsConfig.groovy`

Configures tool installations with static home paths or auto-installers.

**Tool types**: `jdk`, `ant`, `maven`, `gradle`, `xvfb`, `sonarQubeRunner`, `golang`

**Installer types**:
- ID-based: Standard version installers (e.g., Maven `3.5.0`)
- `zip`: Download and extract from URL with optional subdirectory
- `command`: Run a shell command with label-based node assignment

Supports Oracle JDK download credentials via `tools.oracle_jdk_download.username/password`.

### NotifiersConfig
**Config key**: `notifiers`
**File**: `config-handlers/NotifiersConfig.groovy`

Configures notification channels:
- `mail` - SMTP settings, SSL, auth, charset, default suffix
- `slack` - Team domain, bot user, room, credential ID

### PipelineLibrariesConfig
**Config key**: `pipeline_libraries`
**File**: `config-handlers/PipelineLibrariesConfig.groovy`

Creates global pipeline libraries. Each key is the library name with:
- `source.remote` - Git repo URL
- `source.credentialsId` - SSH key credential
- `defaultVersion` - Default branch/tag
- `implicit` - Auto-available in all pipelines (default false)
- Supports non-git SCMs via `retriever.scm.$class`

### SeedJobsConfig
**Config key**: `seed_jobs`
**File**: `config-handlers/SeedJobsConfig.groovy`

Creates pipeline seed jobs that execute JobDSL scripts. Each key is the job name:
- `source.remote/branch/credentialsId` - Git source
- `pipeline` - Path to pipeline script in repo
- `triggers` - SCM polling, periodic, Artifactory triggers
- `executeWhen` - `always`, `firstTimeOnly`, or `never`
- `concurrentBuild` - Allow concurrent builds (default false)
- `parameters` - Job parameters (boolean, string, password, choice, text)

### JobDSLScriptsConfig
**Config key**: `job_dsl_scripts`
**File**: `config-handlers/JobDSLScriptsConfig.groovy`

A lighter alternative to seed jobs. Each list item is an inline JobDSL scriptlet executed at startup and during config updates. No dedicated job is created.

### ScriptApprovalConfig
**Config key**: `script_approval`
**File**: `config-handlers/ScriptApprovalConfig.groovy`

Whitelists method/field signatures for pipeline Groovy scripts. Supports `method`, `staticMethod`, `field`, and `new` signatures.

### ConfigurationAsCodeConfig
**Config key**: `configuration_as_code`
**File**: `config-handlers/ConfigurationAsCodeConfig.groovy`

Enables "mixed-mode" configuration. Embeds native JCasC YAML snippets within the custom config YAML. Used for plugins that don't have a builtin config handler. The handler writes a temporary JCasC YAML file and triggers `ConfigurationAsCode.init()`.

### ArtifactoryConfig
**Config key**: `artifactory`
**File**: `config-handlers/ArtifactoryConfig.groovy`

Configures JFrog Artifactory plugin with server instances, credentials, and connection settings.

### SonarQubeServersConfig
**Config key**: `sonar_qube_servers`
**File**: `config-handlers/SonarQubeServersConfig.groovy`

Configures SonarQube servers with build wrapper, credentials, webhook secrets, and triggers.

### JiraConfig / JiraStepsConfig
**Config keys**: `jira` / `jiraSteps`
**Files**: `config-handlers/JiraConfig.groovy`, `config-handlers/JiraStepsConfig.groovy`

Configures Jira integration plugin and Jira pipeline step sites.

### CheckmarxConfig
**Config key**: `checkmarx`
**File**: `config-handlers/CheckmarxConfig.groovy`

Configures Checkmarx security scanning plugin.

### GitlabConfig
**Config key**: `gitlab`
**File**: `config-handlers/GitlabConfig.groovy`

Configures GitLab plugin settings.

## Custom Config Handler

Users can extend the image with their own handler:

1. Create `/usr/share/jenkins/config-handlers/CustomConfig.groovy` in a derived Docker image
2. Implement `def setup(config) { ... }` and `return this`
3. Add `customConfig:` section to YAML config
4. The handler is invoked last, after all standard handlers
