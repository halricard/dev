# Spec Delta

## MODIFIED Requirements

### Requirement: Port Ownership and Process Management
The system SHALL supervise background services without systemd, classify port occupants (`own`, `stack`, `user`, `alien`, `free`), and prevent destructive port conflicts.

#### Scenario: Starting services with available ports
- **WHEN** user runs `dev start` and default ports (80, 443, 13306, 11025, 18025) are free
- **THEN** system spawns nginx, php-fpm, MySQL, and Mailpit in background with registered PIDs and reports success.

#### Scenario: Starting services with conflicting process from another stack
- **WHEN** user runs `dev start` and a port is occupied by another development sandbox of the same user
- **THEN** system declines to start without force flag, displaying the conflicting PID and advising the use of `-f` or `dev fix -f`.

#### Scenario: Forced start terminating foreign sandbox process
- **WHEN** user runs `dev start -f` or `dev install`
- **THEN** system sends SIGTERM followed by SIGKILL to the conflicting sandbox process, waits for socket release, and starts the core services.

#### Scenario: Detection of capability-enabled service processes
- **WHEN** user runs `dev install` or `dev start` and a stack port (such as 80 or 443) is bound by a capability-bearing sandbox binary
- **THEN** system inspects process command lines and active service state to correctly classify the occupant as `own`, preventing false rogue user conflict warnings or unintended process prompts.
