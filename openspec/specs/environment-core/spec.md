# environment-core Specification

## Purpose

Fornece o núcleo do ambiente de desenvolvimento local, gerenciando a instalação de runtimes estáticos (PHP, Node.js), servidores web e banco de dados sem compilação, controle de processos e portas sem systemd, e certificados HTTPS locais.

## Requirements

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

#### Scenario: Security runtime version resolution
- **WHEN** system resolves pinned versions for PHP and Node runtimes
- **THEN** system resolves PHP runtime version 8.5.12 (patching php2shell) and Node.js official LTS version 24.22.1 with verified archive checksums and download locations.

#### Scenario: Privileged port capability assignment
- **WHEN** user executes `dev install` and provisions the nginx runtime
- **THEN** system grants `cap_net_bind_service=+ep` to the nginx binary so it can bind to ports 80 and 443 without root privileges.

#### Scenario: MySQL client and server library compatibilization
- **WHEN** user executes `dev install` and provisions MySQL runtime
- **THEN** system inspects all MySQL binaries (`mysqld`, `mysql`, `mysqldump`, `mysqladmin`) for missing shared libraries, resolves compatibility links in `lib-compat` for both `libaio.so.1` and `libncurses.so.6`, and verifies executable readiness before setting root credentials.

### Requirement: System Validation and Dependency Verification
The system SHALL verify host architecture and operating system compatibility, validate download checksums, and prompt before installing required system apt packages.

#### Scenario: Running on supported platform
- **WHEN** user initiates installation on Debian/Ubuntu x86_64 or WSL2
- **THEN** system checks for minimal system tools (`ca-certificates`, `curl`, `openssl`, `iproute2`, `procps`, `tar`, `xz-utils`, `zstd`, `libnss3-tools`, `libcap2-bin`, `libncurses6`, `libaio1`/`libnuma1`) and requests user confirmation before running apt commands.

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

#### Scenario: Detection of capability-enabled service processes
- **WHEN** user runs `dev install` or `dev start` and a stack port (such as 80 or 443) is bound by a capability-bearing sandbox binary
- **THEN** system inspects process command lines and active service state to correctly classify the occupant as `own`, preventing false rogue user conflict warnings or unintended process prompts.

### Requirement: Local HTTPS Authority and Certificates
The system SHALL generate an internal Certificate Authority and trust it in the system certificate stores to enable valid HTTPS on `*.localhost` domains.

#### Scenario: Certificate Authority generation
- **WHEN** `dev install` configures local HTTPS
- **THEN** system generates root CA credentials in `~/.dev/ssl`, registers the CA with Windows store (on WSL2) and Linux NSS store using mkcert, and signs wildcard certificates for development vhosts.

### Requirement: Machine Diagnostics and Self-Healing
The system SHALL provide diagnostic checks and automated repair commands to identify and resolve common configuration, port, or orphan process faults.

#### Scenario: Running doctor diagnostic
- **WHEN** user executes `dev doctor`
- **THEN** system verifies service status, port availability, filesystem permissions, binary capabilities for privileged ports, MySQL client library readiness, symlinks, and glibc compatibility, outputting actionable hints for any anomalies.

#### Scenario: Running machine fix
- **WHEN** user executes `dev fix`
- **THEN** system inspects orphan PID files, cleans dead sockets, restores missing binary capabilities for nginx, repairs missing MySQL shared library links in `lib-compat`, restarts downed background daemons, and re-synchronizes generated configuration files.

### Requirement: On-Demand Local PHP Runtime Compilation
The system SHALL provide capabilities to compile standalone, static PHP runtimes from official PHP source code on demand, storing the compiled archives in `runtimes/php/` with checksum verification.

#### Scenario: Compiling missing PHP version from official source
- **WHEN** a compilation of PHP version series (e.g. 8.4) is triggered
- **THEN** the system verifies required host build tools (`gcc`, `g++`, `make`, `autoconf`, `automake`, `libtool`, `bison`, `re2c`, `flex`, `autopoint`, `cmake`, `pkg-config`, `xz-utils`, `bzip2`), obtains the `static-php-cli` (`spc`) utility, navigates into an isolated runtime build directory, provisions the internal `pkg-config` package via `spc install-pkg pkg-config`, configures native glibc compilation (`SPC_LIBC=glibc`), downloads required PHP sources and library dependencies for the sanitized list of extensions, compiles static CLI and FPM binaries, packages the result into `runtimes/php/php-<version>-linux-x86_64.tar.xz`, registers the SHA256 checksum, and provides detailed build logs upon failure.

#### Scenario: Missing system build dependencies
- **WHEN** compilation is requested but required build packages are missing from the host (including `bzip2`)
- **THEN** the system halts before building, identifies the missing system packages, and displays instructions to install them via `apt` or offers automated installation with user confirmation.

#### Scenario: Resolving and caching static-php-cli utility
- **WHEN** on-demand compilation executes and the `spc` executable is not yet cached locally
- **THEN** the system downloads the pinned official `static-php-cli` release archive (`spc-linux-x86_64.tar.gz`), unpacks the binary to `~/.cache/dev/spc/spc`, sets execution permissions, and verifies that the binary responds.

#### Scenario: Sane extension list filtering for spc build
- **WHEN** the compilation process prepares extensions for `spc build`
- **THEN** the system strips built-in or non-extension tokens (`core`, `standard`, `date`, `lexbor`, `random`, `uri`) from the standard extensions string so that `spc build` receives only valid compilable extensions without aborting.

### Requirement: Multi-Version PHP-FPM Service Supervision
The system SHALL concurrently supervise dedicated PHP-FPM daemon instances and sockets for each active PHP version required by hosted projects.

#### Scenario: Starting multi-version PHP-FPM daemons
- **WHEN** projects require different PHP versions (e.g. PHP 8.4 and PHP 8.5) and services start or reload
- **THEN** the system writes versioned configuration files (`php-fpm-<version>.conf`), launches distinct daemon processes (`php-fpm-8.4`, `php-fpm-8.5`), and creates individual Unix domain sockets (`php-8.4.sock`, `php-8.5.sock`).

#### Scenario: Stopping multi-version PHP-FPM daemons
- **WHEN** `dev stop` is executed
- **THEN** the system signals and shuts down all active `php-fpm-<version>` processes and cleans up their socket and PID files.

