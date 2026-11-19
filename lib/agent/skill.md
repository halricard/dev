---
name: dev
description: Run, inspect and administer the "{{PROJECT}}" {{APP_TITLE}} project through the `dev` CLI, and choose the tools for each phase of a feature (specify, design, tasks, execute, verify, deliver). Use it for any task that runs PHP, Composer, Node, the database, the web server, logs, snapshots or the site URL in this project, and before each phase of feature work.
---
<!-- generated-by: dev agent -->
# Working on this project with `dev`

This project runs on `dev`, a Docker-free PHP/Node environment. The project's own PHP, Node, Composer and MySQL are only on the PATH through `dev`. Never call `php`, `composer`, `node`, `npm`, `mysql` or `wp` directly.

- Project: `{{PROJECT}}`
- Application: {{APP_TITLE}}
- Version: {{APP_VERSION}}
- PHP: `{{PHP}}`
- Database: `{{DATABASE}}`
- Docroot: `{{DOCROOT}}`
- URL: {{URL}}

Settings live in `dev.conf` at the project root. Run all commands from inside the project.

## Run commands

- `dev exec <command...>` runs any command with the project's PHP, Node, Composer and MySQL client on the PATH.
- `dev shell` opens an interactive shell with the same environment. Prefer `dev exec` in automation.

## Site lifecycle

- `dev status` shows which services are running.
- `dev up` brings the project up: database, virtual host, schedule and workers.
- `dev down` takes the project down. Files and database stay.
- `dev restart` restarts the machine services. Run it after editing `conf.d/local.ini`.
- `dev fix` recovers a half-started environment. `dev doctor` diagnoses common problems.
- `dev open` opens the site in the browser. `dev open mail` opens Mailpit (captured e-mail). `dev open db` opens Adminer.

## Database

- `dev db query "SELECT ..."` runs SQL against `{{DATABASE}}`. SQL can also come from stdin.
- `dev db export [file.sql.gz]` writes a dump.
- `dev db import <file.sql[.gz]>` drops and recreates the database, then loads the dump. It asks for confirmation.
- Never read or print database credentials. `dev db query` and `dev exec` already provide them.

## Logs and errors

- `dev logs` shows application and web server errors. Check it first when a page fails.
- `dev errors on|off` toggles error display on screen for this project.

## Safety

- Run `dev snapshot <name>` before any destructive step: migrations, database import, search-replace, bulk deletes, core or plugin upgrades. Undo with `dev restore <name>`. `dev snapshots` lists the saved points.
- Do not edit `dev.schedule` or `dev.workers` unless the task asks for it, then run `dev up` to apply the change.
- Do not edit `dev.conf` unless the task asks for it, then run `dev up`.
- `dev passwd` resets the real admin password. Run it only when the user asks. `dev schedule` and `dev worker` show recurring jobs and background processes.
- `dev destroy <name>` deletes the project, its database and snapshots. Never run it without an explicit request.

## Tests

- `dev test` lists the test suites this application offers. `dev test <suite> [args...]` runs one, passing the arguments to the tool. The first run prepares the suite; `dev test init <suite>` prepares it again after an upgrade.
- Run the relevant suite after changing code. Write new tests in the application's own format (see the notes below).
- Test suites use their own tables and data directories. They never touch the site's data.

## Test account

- `dev test user` creates a temporary test account and prints its login and password. Each call sets a new password. `dev test user --no-admin` creates it without admin rights. `dev test user --remove` deletes it, and `dev down` deletes it too.
- Log in with that account when you test in the browser. Never use, read or reset the real administrator account.

{{TOOLS}}{{APP_NOTES}}
