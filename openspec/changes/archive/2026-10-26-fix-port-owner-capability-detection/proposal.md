# Proposal

## Why

During `dev install`, after nginx is granted privileged port capabilities (`cap_net_bind_service=+ep`) and started, subsequent port checks or re-runs display false conflict warnings such as `▲ porta 80 continua ocupada por nginx (pid 133399, dell)` and `▲ porta 443 continua ocupada por nginx (pid 133399, dell)`.
This occurs because capability-bearing binaries are treated as non-dumpable by the Linux kernel, causing unprivileged `readlink -f /proc/<pid>/exe` to return `/proc/<pid>/exe` instead of resolving the executable target in `$DEV_RUNTIME`. As a result, the dev environment incorrectly classifies its own nginx master process as a rogue `user` process rather than `own`, prompting interactive termination or emitting warnings during non-interactive runs. Furthermore, in `take_over_ports`, iterating over port inputs via stdin redirection (`< <(stack_ports)`) interferes with user confirmation prompts.

## What Changes

- Update process executable resolution (`process_exe`) in `lib/services.sh` to use `readlink -e` (or validate against `/proc/` pseudo-paths) so that unreadable capability-bearing symlinks fall back directly to `/proc/<pid>/cmdline` parsing.
- Update `process_mark` in `lib/services.sh` to avoid using unresolvable `/proc/<pid>/exe` paths as distinct process markers, allowing `master_of` to correctly trace worker processes back to the master process for capability binaries.
- Ensure `port_owner` recognizes already-running services by matching against active service PID files and identifying service binaries from command-line arguments when `readlink` is restricted.
- Refactor the port iteration loop in `take_over_ports` to use an explicit file descriptor (e.g. `3< <(stack_ports)`) so that `confirm` prompts do not read or consume subsequent port lines from standard input.
- Add regression tests covering capability-enabled process classification and port conflict resolution.

## Capabilities

### New Capabilities
<!-- None -->

### Modified Capabilities
- `environment-core`: Update `Port Ownership and Process Management` to correctly classify capability-enabled service processes as `own` without false port conflict warnings or broken interactive prompts.

## Impact

- `lib/services.sh`: Fixes `process_exe`, `process_mark`, `port_owner`, and `take_over_ports`.
- `tests/services.bats`: Adds automated tests verifying capability binary classification and port ownership detection.
