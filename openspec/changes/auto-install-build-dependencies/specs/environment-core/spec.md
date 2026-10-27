# Spec Delta

## MODIFIED Requirements

### Requirement: System Validation and Dependency Verification
The system SHALL verify host architecture and operating system compatibility, validate download checksums, and prompt before installing required system apt packages.

#### Scenario: Running on supported platform
- **WHEN** user initiates installation on Debian/Ubuntu x86_64 or WSL2
- **THEN** system checks for minimal system tools (`ca-certificates`, `curl`, `openssl`, `iproute2`, `procps`, `tar`, `xz-utils`, `zstd`, `libnss3-tools`, `libcap2-bin`, `libncurses6`, `libaio1`/`libnuma1`) as well as runtime build dependencies (`gcc`, `g++`, `make`, `autoconf`, `automake`, `libtool`, `bison`, `re2c`, `flex`, `autopoint`, `cmake`, `pkg-config`), and requests user confirmation before running apt commands.

#### Scenario: Running on unsupported platform
- **WHEN** user executes `dev install` on an unsupported operating system or architecture
- **THEN** system aborts execution with a clear diagnostic message explaining supported environments.

### Requirement: Machine Diagnostics and Self-Healing
The system SHALL provide diagnostic checks and automated repair commands to identify and resolve common configuration, port, or orphan process faults.

#### Scenario: Running doctor diagnostic
- **WHEN** user executes `dev doctor`
- **THEN** system verifies service status, port availability, build toolchain packages, filesystem permissions, binary capabilities for privileged ports, MySQL client library readiness, symlinks, and glibc compatibility, outputting actionable hints for any anomalies.

#### Scenario: Running machine fix
- **WHEN** user executes `dev fix`
- **THEN** system inspects orphan PID files, cleans dead sockets, restores missing binary capabilities for nginx, repairs missing MySQL shared library links in `lib-compat`, restarts downed background daemons, and re-synchronizes generated configuration files.

### Requirement: On-Demand Local PHP Runtime Compilation
The system SHALL provide capabilities to compile standalone, static PHP runtimes from official PHP source code on demand, storing the compiled archives in `runtimes/php/` with checksum verification.

#### Scenario: Compiling missing PHP version from official source
- **WHEN** a compilation of PHP version series (e.g. 8.4) is triggered
- **THEN** the system verifies required build tools (`gcc`, `make`, `autoconf`, etc.), downloads official PHP source, compiles static CLI and FPM binaries with standard extensions (without SQLite), packages the result into `runtimes/php/php-<version>-linux-x86_64.tar.xz`, and registers the SHA256 checksum.

#### Scenario: Missing system build dependencies
- **WHEN** compilation is requested but required build packages are missing from the host
- **THEN** the system halts before building, identifies the missing system packages, and displays instructions to install them via `apt`.

#### Scenario: Missing system build dependencies with interactive installation
- **WHEN** compilation is requested and required build packages are missing in an interactive session
- **THEN** the system identifies missing packages, prompts the user to install them via `sudo apt`, installs them upon approval, and continues compilation seamlessly.
