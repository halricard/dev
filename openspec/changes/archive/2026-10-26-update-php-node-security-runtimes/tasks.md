# Tasks

## 1. PHP Runtime Manifest Security Update

- [x] 1.1 Update `PHP_RUNTIME_VERSION` to `8.5.12`, update `PHP_RUNTIME_FILE` path, and update `PHP_RUNTIME_SHA256` in `runtimes/manifest.sh`. Verify syntax with `bash -n runtimes/manifest.sh`.

## 2. Node.js Version Bump

- [x] 2.1 Update `NODE_VERSION` to `24.22.1` in `versions.sh`. Verify with `dev versions` output displaying Node 24.22.1 and `bash -n versions.sh`.

## 3. Test Suites and System Verification

- [x] 3.1 Update version assertions for PHP 8.5.12 and Node 24.22.1 in `tests/releases.bats`. Verify by running `tools/test.sh tests/releases.bats`.
- [x] 3.2 Run `tools/check.sh` and `dev install --plan` to verify that dry-run planning succeeds and reports the patched PHP and Node.js versions with zero syntax or linter errors.

## Workflow follow-up

- Sync specs and archive the change once implementation is complete.
