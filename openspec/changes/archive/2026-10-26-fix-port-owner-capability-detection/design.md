# Design

## Context

See `proposal.md` for problem background.

On Linux, when a binary has Linux capabilities (specifically `setcap cap_net_bind_service=+ep` for nginx), the kernel marks the executed process as non-dumpable (`PR_SET_DUMPABLE = 0`). Consequently:
1. Ownership of `/proc/<pid>/exe` appears restricted to root, and unprivileged user calls to `readlink /proc/<pid>/exe` fail with `EACCES`.
2. Using `readlink -f /proc/<pid>/exe` returns the literal string `"/proc/<pid>/exe"` because GNU `readlink -f` outputs unresolved pathnames upon encountering unresolvable symlinks.
3. Because `"/proc/<pid>/exe"` is non-empty but does not match `"$DEV_RUNTIME"/*`, `process_exe` fails to recognize the executable as a dev runtime binary and never falls back to `/proc/<pid>/cmdline`.
4. As a result, `port_owner` classifies the running nginx master process as `user` (or `alien`) instead of `own`.
5. When `take_over_ports` runs, it misidentifies nginx as an alien or foreign user process, attempting to confirm process termination. In addition, `while IFS= read -r port; do ... done < <(stack_ports)` binds file descriptor 0 (standard input) to the port list stream, breaking `confirm`'s `read -r` prompt.

## Goals / Non-Goals

**Goals:**
- Correctly identify capability-enabled processes (such as nginx) as `own` in `process_exe`, `process_mark`, and `port_owner`.
- Ensure `find_own_process` can locate running capability-enabled processes even if the pid file was removed or unreferenced.
- Isolate the stream in `take_over_ports` to file descriptor 3 so that user prompts on fd 0 operate as intended.
- Eliminate false `▲ porta 80 continua ocupada` warnings during `dev install` and `dev start`.

**Non-Goals:**
- Modifying how capabilities are applied or altering systemd / sudo configurations.
- Changing port numbers or nginx configuration generation.

## Decisions

### 1. Robust Executable Resolution in `process_exe`
Use `readlink -e "/proc/$pid/exe"` instead of `readlink -f`. Validate that the result is non-empty and does not begin with `"/proc/"`. If `readlink -e` fails or returns a `/proc/` reference, immediately proceed to inspecting `/proc/<pid>/cmdline`.
- *Alternatives considered*: Sourcing `sudo ss` for all process checks. Rejected because `dev` operates without root privileges and should not trigger unnecessary sudo credential requests or fail in unauthenticated contexts.

### 2. Tracing Process Ancestry in `process_mark`
In `process_mark`, ensure `exe` resolution uses `readlink -e` and rejects `"/proc/"*`. If the executable link is unreadable, fall back to `comm:<comm>` (e.g. `comm:nginx`). This allows `master_of` to correctly match nginx worker processes with their parent master process.

### 3. Service PID Verification in `port_owner`
In `port_owner`, when checking process ownership for user-owned listeners on stack ports, verify whether `OWNER_PID` matches the registered PID in `~/.dev/services/run/<service>.pid`. If it matches and the process is alive, immediately classify it as `own`.

### 4. File Descriptor Isolation in `take_over_ports`
Change the port loop to `while IFS= read -r -u 3 port; do ... done 3< <(stack_ports)`. This preserves standard input for interactive prompts in `confirm` and prevents the loop from consuming port lines as answers.

## Risks / Trade-offs

- **[Risk]** `/proc/<pid>/cmdline` may contain spaces or unusual escaping.
  → **Mitigation:** Parse using null-byte delimiters (`tr '\0' '\n'`) as already done in `process_argv`, searching specifically for `$DEV_RUNTIME/*` binary paths.
