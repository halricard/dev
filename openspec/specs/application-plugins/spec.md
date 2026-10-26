# application-plugins Specification

## Purpose

Define a arquitetura modular de plugins para o dev, permitindo a instalação incremental de aplicações (WordPress, Laravel e Moodle), gerenciamento de dependências específicas e execução de receitas de novos projetos.

## Requirements

### Requirement: Plugin Management and Discovery
The system SHALL provide commands to list, install, and remove application plugins incrementally without baking application tools into the core installation.

#### Scenario: Listing plugins
- **WHEN** user executes `dev plugin list`
- **THEN** system displays available application plugins, indicating whether each plugin is installed, version/status, and associated tools.

#### Scenario: Installing a plugin
- **WHEN** user executes `dev plugin install <name>` for an available plugin (such as `wordpress`, `laravel`, or `moodle`)
- **THEN** system provisions application-specific CLI binaries and templates into `~/.dev/plugins/<name>` and registers the plugin recipe in active recipes.

#### Scenario: Removing an installed plugin
- **WHEN** user executes `dev plugin remove <name>`
- **THEN** system unregisters the recipe, removes plugin-specific runtime binaries, and informs the user that existing projects remain intact.

### Requirement: Recipe Hook Interface Contract
The system SHALL define and execute standardized recipe hooks for application plugins, ensuring safe function namespace cleanup between executions.

#### Scenario: Loading and executing a recipe
- **WHEN** a plugin recipe is loaded for project scaffolding or adoption
- **THEN** system unsets previously loaded recipe functions (`recipe_*`), loads the target recipe script, and safely invokes declared hooks (`recipe_title`, `recipe_docroot`, `recipe_install`, `recipe_restore`, etc.).

### Requirement: Project Scaffolding via Installed Plugins
The system SHALL enforce that `dev new <app> <site>` requires the corresponding application plugin to be installed.

#### Scenario: Creating a project with an installed plugin
- **WHEN** user executes `dev new <app> <name>` and `<app>` plugin is installed
- **THEN** system executes the plugin's installation routine, provisions project directories, configures database and credentials, brings the site up, and displays access instructions.

#### Scenario: Attempting creation with an uninstalled plugin
- **WHEN** user executes `dev new <app> <name>` but `<app>` plugin has not been installed
- **THEN** system halts before creating files, printing an error and a hint recommending `dev plugin install <app>`.

### Requirement: WordPress Application Plugin
The system SHALL provide a WordPress plugin implementing WP-CLI provisioning, database setup, secure `wp-config.php` generation, and WP-Cron scheduling.

#### Scenario: Provisioning WordPress project
- **WHEN** user creates a project using the WordPress plugin
- **THEN** system fetches WordPress, configures MySQL database and salts, runs CLI installation with generated admin credentials, writes `.gitignore` white-list, and configures 60-second cron schedule.

### Requirement: Laravel Application Plugin
The system SHALL provide a Laravel plugin implementing `laravel-installer` provisioning, support for MySQL and SQLite, environment configuration, migration runs, queue listeners, and schedule execution.

#### Scenario: Provisioning Laravel project
- **WHEN** user creates a project using the Laravel plugin
- **THEN** system prompts for database engine (MySQL/SQLite), runs official Laravel installer, injects sandboxed credentials and Mailpit into `.env`, runs migrations, and configures `queue:listen`, `npm run dev`, and `schedule:run`.

### Requirement: Moodle Application Plugin
The system SHALL provide a Moodle plugin implementing tarball branch downloads, secure nested data directory layout (`app/` and `data/`), CLI database installation, and cron task execution.

#### Scenario: Provisioning Moodle project
- **WHEN** user creates a project using the Moodle plugin
- **THEN** system unpacks Moodle into `app/`, creates non-public `data/` directory with 0750 permissions, generates `config.php` with `utf8mb4_unicode_ci` and deprecation suppression, runs `admin/cli/install_database.php`, and configures `cron.php` schedule.
