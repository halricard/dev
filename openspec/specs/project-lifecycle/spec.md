# project-lifecycle Specification

## Purpose

Gerencia o ciclo de vida completo de projetos individuais de desenvolvimento, incluindo criação, adoção (`dev.conf`), vhosts, agendamento de tarefas, workers contínuos, snapshots e execução em ambiente isolado.

## Requirements

### Requirement: Project Configuration and Adoption
The system SHALL support declarative project configuration via `dev.conf` and automatic detection of existing project frameworks and docroots during project initialization.

#### Scenario: Initializing an existing project
- **WHEN** user runs `dev init` inside an existing codebase directory
- **THEN** system inspects entry points (`public/index.php`, `index.php`), detects configured application type and database name, and writes a standard `dev.conf`.

#### Scenario: Destroying a project
- **WHEN** user executes `dev destroy <name>` and types the confirmation name
- **THEN** system stops running workers, drops the associated database, removes snapshot backups and virtual host links, while leaving project files intact unless explicitly directed.

### Requirement: Idempotent Project Bring-Up and Teardown
The system SHALL bring a project online using `dev up` and take it offline with `dev down` idempotently without data loss.

#### Scenario: Running dev up inside a project
- **WHEN** user executes `dev up` in a project with a valid `dev.conf`
- **THEN** system verifies core services are active, creates database if missing, generates and reloads nginx vhost, trusts HTTPS host, and starts declared workers and schedule.

#### Scenario: Running dev down
- **WHEN** user executes `dev down` inside an active project directory or with project name
- **THEN** system gracefully terminates active background workers and schedulers for that site, removes nginx virtual host entry, and leaves code and database untouched.

### Requirement: Isolated Execution Environment
The system SHALL provide subcommands to execute scripts and interactive shells with the project-specific PHP, Node.js, and Composer binaries prepended to PATH.

#### Scenario: Executing command in project context
- **WHEN** user runs `dev exec php -v` or `dev exec composer test`
- **THEN** system executes the requested command using the configured runtime paths and environment variables of that project without global PATH contamination.

#### Scenario: Opening interactive project shell
- **WHEN** user runs `dev shell` inside a configured project directory
- **THEN** system opens a subshell with project runtimes in PATH and contextual environment variables exported.

### Requirement: Background Schedule and Worker Supervision
The system SHALL supervise recurring scheduled tasks defined in `dev.schedule` and persistent worker processes defined in `dev.workers`.

#### Scenario: Starting project schedule
- **WHEN** project is brought up with a valid `dev.schedule` containing interval and command pairs
- **THEN** system runs a supervisor loop triggering commands at specified intervals, recording exit codes and timestamps in execution logs.

#### Scenario: Supervising background workers
- **WHEN** project defines persistent workers in `dev.workers` (such as queue listeners or dev asset servers)
- **THEN** system launches processes in background, monitors process health, and restarts them upon unexpected termination.

### Requirement: Database Operations and Point-in-time Snapshots
The system SHALL provide utility commands to query, export, import, and create reproducible snapshots of project files and databases.

#### Scenario: Querying project database
- **WHEN** user runs `dev db query "SELECT 1"` inside a project with a database configured
- **THEN** system routes the query through the sandbox MySQL CLI with sandboxed credentials and prints results to stdout.

#### Scenario: Creating a project snapshot
- **WHEN** user runs `dev snapshot my-checkpoint`
- **THEN** system dumps the project MySQL database, archives untracked files and state into `~/.dev/snapshots/<project>/`, and registers the snapshot metadata.

#### Scenario: Restoring a snapshot
- **WHEN** user runs `dev restore my-checkpoint`
- **THEN** system confirms action, restores database schema and data from the snapshot dump, and recovers archived filesystem state.

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

