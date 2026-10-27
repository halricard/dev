# Tasks

## 1. Process and Executable Resolution Fixes

- [x] 1.1 Update `process_exe` in `lib/services.sh` to use `readlink -e` and reject `/proc/` paths, falling back to `/proc/<pid>/cmdline` parsing for capability-bearing binaries. Verify with a test script against running capability-enabled processes.
- [x] 1.2 Update `process_mark` in `lib/services.sh` to reject `/proc/` symlink targets and fall back to `comm:<name>`, ensuring `master_of` resolves worker processes to the master process.
- [x] 1.3 Update `port_owner` in `lib/services.sh` to check active service PID files when classifying listeners on stack ports.

## 2. Port Iteration Stream Isolation

- [x] 2.1 Refactor `take_over_ports` in `lib/services.sh` to read ports via file descriptor 3 (`3< <(stack_ports)`) so that interactive prompts on standard input are not consumed.

## 3. Automated Tests and Verification

- [x] 3.1 Add automated tests in `tests/services.bats` covering `process_exe` and `port_owner` classification for capability-restricted binaries and simulated process command lines.
- [x] 3.2 Add automated tests in `tests/services.bats` verifying `take_over_ports` behavior with running stack services and interactive prompt isolation.
- [x] 3.3 Run `./tools/check.sh` and `./dev status` to verify repository quality gates and confirm absence of port conflict warnings.
