# Spec Delta: environment-core

## MODIFIED Requirements

### Requirement: On-Demand Local PHP Runtime Compilation
The system SHALL provide capabilities to compile standalone, static PHP runtimes from official PHP source code on demand, storing the compiled archives in `runtimes/php/` with checksum verification.

#### Scenario: Compiling missing PHP version from official source
- **WHEN** a compilation of PHP version series (e.g. 8.4) is triggered
- **THEN** the system verifies required build tools (`gcc`, `g++`, `make`, `autoconf`, `automake`, `libtool`, `bison`, `re2c`, `flex`, `autopoint`, `cmake`, `pkg-config`, `xz-utils`, `bzip2`), obtains the `static-php-cli` utility by extracting its official release archive (`.tar.gz`), downloads official PHP source, compiles static CLI and FPM binaries with standard extensions (without SQLite), packages the result into `runtimes/php/php-<version>-linux-x86_64.tar.xz`, and registers the SHA256 checksum.

#### Scenario: Missing system build dependencies
- **WHEN** compilation is requested but required build packages are missing from the host (including `bzip2`)
- **THEN** the system halts before building, identifies the missing system packages, and displays instructions to install them via `apt` or offers automated installation with user confirmation.

#### Scenario: Resolving and caching static-php-cli utility
- **WHEN** on-demand compilation executes and the `spc` executable is not yet cached locally
- **THEN** the system downloads the pinned official `static-php-cli` release archive (`spc-linux-x86_64.tar.gz`), unpacks the binary to `~/.cache/dev/spc/spc`, sets execution permissions, and verifies that the binary responds.
