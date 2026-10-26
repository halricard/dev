# Spec Delta

## MODIFIED Requirements

### Requirement: System Validation and Dependency Verification
The system SHALL verify host architecture and operating system compatibility, validate download checksums, and prompt before installing required system apt packages.

#### Scenario: Running on supported platform
- **WHEN** user initiates installation on Debian/Ubuntu x86_64 or WSL2
- **THEN** system checks for minimal system tools (`ca-certificates`, `curl`, `openssl`, `iproute2`, `procps`, `tar`, `xz-utils`, `zstd`, `libnss3-tools`, `libcap2-bin`, `libaio1`/`libnuma1`) and requests user confirmation before running apt commands.

#### Scenario: Running on unsupported platform
- **WHEN** user executes `dev install` on an unsupported operating system or architecture
- **THEN** system aborts execution with a clear diagnostic message explaining supported environments.

### Requirement: Fast Non-compilation Installation
The system SHALL provision PHP, nginx, MySQL, Node.js, Composer, Mailpit, Adminer, and mkcert using precompiled static archives or official prebuilt binaries into `~/.dev` without compiling from source.

#### Scenario: Standard installation run
- **WHEN** user executes `dev install`
- **THEN** system checks system requirements, downloads prebuilt binaries to `~/.cache/dev`, extracts runtimes into `~/.dev/runtime`, initializes database and configuration, and brings up core services.

#### Scenario: Dry-run planning
- **WHEN** user executes `dev install --plan`
- **THEN** system outputs the versions, origins, and target paths of all components to be installed, verifies download URLs, and terminates without modifying disk state or system packages.

#### Scenario: Security runtime version resolution
- **WHEN** system resolves pinned versions for PHP and Node runtimes
- **THEN** system resolves PHP runtime version 8.5.12 (patching php2shell) and Node.js official LTS version 24.22.1 with verified archive checksums and download locations.

#### Scenario: Privileged port capability assignment
- **WHEN** user executes `dev install` and provisions the nginx runtime
- **THEN** system grants `cap_net_bind_service=+ep` to the nginx binary so it can bind to ports 80 and 443 without root privileges.

### Requirement: Machine Diagnostics and Self-Healing
The system SHALL provide diagnostic checks and automated repair commands to identify and resolve common configuration, port, or orphan process faults.

#### Scenario: Running doctor diagnostic
- **WHEN** user executes `dev doctor`
- **THEN** system verifies service status, port availability, filesystem permissions, binary capabilities for privileged ports, symlinks, and glibc compatibility, outputting actionable hints for any anomalies.

#### Scenario: Running machine fix
- **WHEN** user executes `dev fix`
- **THEN** system inspects orphan PID files, cleans dead sockets, restores missing binary capabilities for nginx, restarts downed background daemons, and re-synchronizes generated configuration files.
