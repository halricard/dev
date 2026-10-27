# Spec Delta

## ADDED Requirements

### Requirement: Interactive Missing PHP Runtime Prompt
The system SHALL detect when a project's configured or recipe-requested PHP version is missing from the local sandbox and prompt the user interactively before aborting, allowing on-demand compilation from official sources.

#### Scenario: User accepts compilation during project creation
- **WHEN** user runs `dev new <app> <name>` requiring a PHP version that is not installed or available in `runtimes/php/`
- **THEN** the system prompts `"O <app> requer PHP <versão>, que ainda não foi compilado. Deseja compilar agora a partir do fonte oficial? [S/n]"`, compiles the runtime upon positive response, installs it to `~/.dev/runtime/php/<versão>`, and continues project creation without error.

#### Scenario: User declines compilation during project creation
- **WHEN** user runs `dev new <app> <name>` requiring an uncompiled PHP version and declines the compilation prompt
- **THEN** the system aborts project scaffolding cleanly, prints a diagnostic message, and does not leave partially created files or databases.

#### Scenario: Bringing up project with uncompiled PHP version
- **WHEN** user executes `dev up` in a project whose `dev.conf` declares a PHP version that is neither in `~/.dev/runtime/php/` nor in `runtimes/php/`
- **THEN** the system prompts whether to compile the required version, executes compilation and sandbox extraction upon confirmation, and brings the site online.
