# Spec Delta

## MODIFIED Requirements

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
