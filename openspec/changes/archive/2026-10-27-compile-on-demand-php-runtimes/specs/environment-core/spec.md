# Spec Delta

## ADDED Requirements

### Requirement: On-Demand Local PHP Runtime Compilation
The system SHALL provide capabilities to compile standalone, static PHP runtimes from official PHP source code on demand, storing the compiled archives in `runtimes/php/` with checksum verification.

#### Scenario: Compiling missing PHP version from official source
- **WHEN** a compilation of PHP version series (e.g. 8.4) is triggered
- **THEN** the system verifies required build tools (`gcc`, `make`, `autoconf`, etc.), downloads official PHP source, compiles static CLI and FPM binaries with standard extensions (without SQLite), packages the result into `runtimes/php/php-<version>-linux-x86_64.tar.xz`, and registers the SHA256 checksum.

#### Scenario: Missing system build dependencies
- **WHEN** compilation is requested but required build packages are missing from the host
- **THEN** the system halts before building, identifies the missing system packages, and displays instructions to install them via `apt`.

### Requirement: Multi-Version PHP-FPM Service Supervision
The system SHALL concurrently supervise dedicated PHP-FPM daemon instances and sockets for each active PHP version required by hosted projects.

#### Scenario: Starting multi-version PHP-FPM daemons
- **WHEN** projects require different PHP versions (e.g. PHP 8.4 and PHP 8.5) and services start or reload
- **THEN** the system writes versioned configuration files (`php-fpm-<version>.conf`), launches distinct daemon processes (`php-fpm-8.4`, `php-fpm-8.5`), and creates individual Unix domain sockets (`php-8.4.sock`, `php-8.5.sock`).

#### Scenario: Stopping multi-version PHP-FPM daemons
- **WHEN** `dev stop` is executed
- **THEN** the system signals and shuts down all active `php-fpm-<version>` processes and cleans up their socket and PID files.
