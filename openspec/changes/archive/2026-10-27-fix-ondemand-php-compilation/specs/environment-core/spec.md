# Spec Delta

## MODIFIED Requirements

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
