# Testing

## Overview

Tests are integration tests that run a real Jenkins instance in Docker and validate configuration via Jenkins CLI + Groovy scripts. The primary test runner is [BATS (Bash Automated Testing System)](https://github.com/bats-core/bats-core).

## Running Tests

```bash
# Run all tests (default target)
make test-all

# Run tests for a specific distribution
make test-alpine
make test-debian
make test-jdk21

# Build without testing
make build-alpine
make build-debian
make build-jdk21

# Update plugins to latest versions
make update-plugins

# Create a release tag
make release
```

## Test Infrastructure

### Test Docker Compose Files

| File | Purpose |
|------|---------|
| `tests/docker-compose-simple.yml` | Jenkins test container with configurable env vars (config URL, polling interval, admin user) |
| `tests/docker-compose-consul.yml` | Consul (v0.6.4) + Vault (v0.9.6) services for envconsul integration tests |

Both use an external Docker network `jenkins-docker-bridge` for cross-compose connectivity.

### Test Helpers (`tests/tests_helpers.bash`)

Shared functions used across all test suites:
- `dc_up()` / `dc_down()` - Docker compose lifecycle
- `dc_exec()` - Execute commands in a service container
- `wait_for_jenkins()` - Health check with retry logic
- `create_network()` / `remove_network()` - Docker network management
- `wait_for_container()` / `wait_for_container_log()` - Container readiness polling
- `create_config_fixtures()` - Prepare test YAML configurations

### Jenkins CLI Runner (`tests/run-jenkins-groovy.sh`)

Downloads `jenkins-cli.jar` from the running Jenkins instance and executes Groovy scripts via:
```bash
java -jar jenkins-cli.jar -s http://localhost:8080/ -auth <user>:<token> groovy = < script.groovy
```

Uses the admin API token stored in `/dev/shm/.api-token`.

## Test Suites

### 1. Config Handlers Tests
**File**: `tests/config-handlers-tests.bats`
**Tests**: 18 handlers

Each test follows the pattern:
1. Start Jenkins with config fixture via docker-compose
2. Wait for Jenkins to be healthy
3. Execute a Groovy assertion script via Jenkins CLI
4. The Groovy script loads the config handler and validates the Jenkins instance state
5. Stop Jenkins

**Tested handlers**:
| Test Name | Handler | Validation |
|-----------|---------|------------|
| Sanity | - | Plugin health check, no failed plugins |
| ConfigurationAsCode | configuration_as_code | JCasC snippets applied |
| Security | security | Realm, permissions, security options |
| Clouds | clouds | ECS/Kubernetes/Docker cloud configs |
| Creds | credentials | All credential types created |
| Tools | tools | Tool installations configured |
| EnvironmentVars | environment | Global env vars set |
| Gitlab | gitlab | GitLab plugin configured |
| Jira | jira | Jira sites configured |
| JiraSteps | jiraSteps | Jira step sites configured |
| Notifiers | notifiers | Mail/Slack configured |
| PipelineLibraries | pipeline_libraries | Libraries with SCM sources |
| ScriptApproval | script_approval | Method signatures whitelisted |
| SeedJobs | seed_jobs | Jobs created with triggers |
| JobDSLScripts | job_dsl_scripts | Inline DSL scripts executed |
| SonarQubeServers | sonar_qube_servers | SonarQube servers configured |
| RemoveMasterEnvVars | remove_master_envvars | Env vars hidden from System Info |

### 2. Config Deep Merge Tests
**File**: `tests/config-deep-merge-tests.bats`

Tests that multiple YAML config files are deep-merged correctly:
- Configs from `dir1/` (base config)
- Configs from `dir2/` (override)
- Configs from `dir3/` (multiple files, sorted alphabetically)

The deep merge algorithm (in `fetchconfig.py`) recursively merges nested maps, with later sources overriding earlier ones. Lists are replaced, not concatenated.

**Test fixtures**:
- `tests/data/config-fixtures/config-in-dir1.yml`
- `tests/data/config-fixtures/config-in-dir2.yml`
- `tests/data/config-fixtures/config-in-dir3-1.yml`
- `tests/data/config-fixtures/config-in-dir3-2.yml`

### 3. Envconsul Tests
**File**: `tests/envconsule-tests.bats`

Integration tests for Consul and Vault dynamic secret fetching:
1. Start Consul and Vault via docker-compose-consul.yml
2. Bootstrap Vault and put secrets in Consul KV store
3. Start Jenkins with `ENVCONSUL_CONSUL_PREFIX` and `ENVCONSUL_VAULT_PREFIX`
4. Verify credentials loaded from both Consul and Vault

**Consul data** (`tests/data/consul-data.json`):
- Base64-encoded values in KV store
- Key format matches the `ENVVARS_DIRS` naming convention

**Vault data**:
- Secrets stored at `secret/jenkins`
- Values used in config YAML via `${SECRET_VAR}` substitution

### 4. Environment Variables from Files Tests
**File**: `tests/config-envvars-from-files.bats`

Tests the `ENVVARS_DIRS` feature for Kubernetes Secret volume mapping:
1. Create files in test directories
2. Start Jenkins with `ENVVARS_DIRS` pointing to those directories
3. Verify environment variables are created from file contents

**Naming convention**: `<DIRECTORY_NAME>_<FILE_NAME>` uppercased and sanitized (dots/hyphens become underscores)

**Test fixtures**:
- `tests/data/config-fixtures/config-envvars-secret1.yml`
- `tests/data/config-fixtures/config-envvars-secret2.yml`

## Groovy Test Scripts

Located in `tests/groovy/`, organized by test suite:

**config-handlers/**: Per-handler validation scripts that:
- Load the config YAML fixture
- Call the handler's `setup()` method
- Assert against Jenkins instance state (realms, credentials, clouds, etc.)
- Example: `SecurityConfigTest.groovy` validates LDAP realm properties, AD configuration, SAML settings

**envconsul/**: Assertion scripts for Consul/Vault credentials:
- `AssertCredsFromConsul.groovy` - Verifies credentials loaded from Consul KV
- `AssertCredsFromVault.groovy` - Verifies credentials loaded from Vault

**deep-merge/**: Assertion scripts for merged configs:
- `AssertCredsFromDir1.groovy` through `AssertCredsFromDir32.groovy` - Verify each merge layer

**envvars/**: Assertion scripts for file-based env vars:
- `AssertCredsFromSecret1.groovy` / `AssertCredsFromSecret2.groovy` - Verify env vars from files

## CI/CD Pipeline

GitHub Actions workflow (`.github/workflows/main.yml`):

```
Push to any branch
  |
  +-- Test matrix: [debian, alpine, jdk21]
  |     +-- bats-core/bats-action@2.0.0
  |     +-- make test-${{ matrix.dist }}
  |
  +-- If tag v*:
  |     +-- Docker login (Hub + GHCR)
  |     +-- ./publish.sh <tag>
  |         (builds and pushes 9 image variants)
  |
  +-- If master branch:
        +-- Docker login (Hub + GHCR)
        +-- ./publish.sh latest
```

## Writing New Tests

To add a test for a new config handler:

1. Create a YAML fixture in `tests/data/config-fixtures/`
2. Create a Groovy assertion script in `tests/groovy/config-handlers/<Handler>Test.groovy`
3. Add a BATS test case in `tests/config-handlers-tests.bats` following the existing pattern:
```bash
@test "Test <Handler>Config" {
    dc_up "<compose-file>"
    wait_for_jenkins "<service-name>"
    run run_jenkins_groovy "<service-name>" "<test-script>"
    [ "$status" -eq 0 ]
    dc_down "<compose-file>"
}
```
