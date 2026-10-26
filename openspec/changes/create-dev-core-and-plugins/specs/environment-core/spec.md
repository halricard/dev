# Spec Delta

## Purpose

Fornece o núcleo do ambiente de desenvolvimento local, gerenciando a instalação de runtimes estáticos (PHP, Node.js), servidores web e banco de dados sem compilação, controle de processos e portas sem systemd, e certificados HTTPS locais.

## ADDED Requirements

### Requirement: CLI Dispatcher and Help
The system SHALL provide an executable command `dev` that dispatches subcommands to modular library scripts and displays contextual help and version information.

#### Scenario: Running dev without arguments
- **WHEN** user executes `dev` or `dev help`
- **THEN** system prints structured usage instructions with available environment and project commands, without syntax errors or unquoted backticks.

#### Scenario: Running command via symlink in PATH
- **WHEN** user executes `dev` from any working directory through a symlink in `~/.local/bin` or `/usr/local/bin`
- **THEN** system resolves the canonical path of the script and locates internal libraries relative to the project root.

### Requirement: Fast Non-compilation Installation
The system SHALL provision PHP, nginx, MySQL, Node.js, Composer, Mailpit, Adminer, and mkcert using precompiled static archives or official prebuilt binaries into `~/.dev` without compiling from source.

#### Scenario: Standard installation run
- **WHEN** user executes `dev install`
- **THEN** system checks system requirements, downloads prebuilt binaries to `~/.cache/dev`, extracts runtimes into `~/.dev/runtime`, initializes database and configuration, and brings up core services.

#### Scenario: Dry-run planning
- **WHEN** user executes `dev install --plan`
- **THEN** system outputs the versions, origins, and target paths of all components to be installed, verifies download URLs, and terminates without modifying disk state or system packages.

### Requirement: System Validation and Dependency Verification
The system SHALL verify host architecture and operating system compatibility, validate download checksums, and prompt before installing required system apt packages.

#### Scenario: Running on supported platform
- **WHEN** user initiates installation on Debian/Ubuntu x86_64 or WSL2
- **THEN** system checks for minimal system tools (`ca-certificates`, `curl`, `openssl`, `iproute2`, `procps`, `tar`, `xz-utils`, `zstd`, `libnss3-tools`, `libaio1`/`libnuma1`) and requests user confirmation before running apt commands.

#### Scenario: Running on unsupported platform
- **WHEN** user executes `dev install` on an unsupported operating system or architecture
- **THEN** system aborts execution with a clear diagnostic message explaining supported environments.

### Requirement: Port Ownership and Process Management
The system SHALL supervise background services without systemd, classify port occupants (`own`, `stack`, `user`, `alien`, `free`), and prevent destructive port conflicts.

#### Scenario: Starting services with available ports
- **WHEN** user runs `dev start` and default ports (80, 443, 13306, 11025, 18025) are free
- **THEN** system spawns nginx, php-fpm, MySQL, and Mailpit in background with registered PIDs and reports success.

#### Scenario: Starting services with conflicting process from another stack
- **WHEN** user runs `dev start` and a port is occupied by another development sandbox of the same user
- **THEN** system declines to start without force flag, displaying the conflicting PID and advising the use of `-f` or `dev fix -f`.

#### Scenario: Forced start terminating foreign sandbox process
- **WHEN** user runs `dev start -f` or `dev install`
- **THEN** system sends SIGTERM followed by SIGKILL to the conflicting sandbox process, waits for socket release, and starts the core services.

### Requirement: Local HTTPS Authority and Certificates
The system SHALL generate an internal Certificate Authority and trust it in the system certificate stores to enable valid HTTPS on `*.localhost` domains.

#### Scenario: Certificate Authority generation
- **WHEN** `dev install` configures local HTTPS
- **THEN** system generates root CA credentials in `~/.dev/ssl`, registers the CA with Windows store (on WSL2) and Linux NSS store using mkcert, and signs wildcard certificates for development vhosts.

### Requirement: Machine Diagnostics and Self-Healing
The system SHALL provide diagnostic checks and automated repair commands to identify and resolve common configuration, port, or orphan process faults.

#### Scenario: Running doctor diagnostic
- **WHEN** user executes `dev doctor`
- **THEN** system verifies service status, port availability, filesystem permissions, symlinks, and glibc compatibility, outputting actionable hints for any anomalies.

#### Scenario: Running machine fix
- **WHEN** user executes `dev fix`
- **THEN** system inspects orphan PID files, cleans dead sockets, restarts downed background daemons, and re-synchronizes generated configuration files.
