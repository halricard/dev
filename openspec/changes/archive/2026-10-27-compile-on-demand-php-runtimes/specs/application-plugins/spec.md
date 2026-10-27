# Spec Delta

## MODIFIED Requirements

### Requirement: Moodle Application Plugin
The system SHALL provide a Moodle plugin implementing tarball branch downloads, secure nested data directory layout (`app/` and `data/`), CLI database installation, cron task execution, and guaranteed PHP 8.4 runtime availability.

#### Scenario: Provisioning Moodle project
- **WHEN** user creates a project using the Moodle plugin
- **THEN** system unpacks Moodle into `app/`, creates non-public `data/` directory with 0750 permissions, generates `config.php` with `utf8mb4_unicode_ci` and deprecation suppression, runs `admin/cli/install_database.php`, and configures `cron.php` schedule.

#### Scenario: Provisioning Moodle project with uncompiled PHP 8.4
- **WHEN** user creates a project using the Moodle plugin on an environment lacking PHP 8.4
- **THEN** system prompts the user to compile PHP 8.4 from official source, compiles and stores it in `runtimes/php/`, installs it to the sandbox, and proceeds with Moodle database installation using PHP 8.4 CLI.
