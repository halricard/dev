# Proposal

## Why

A critical security vulnerability (`php2shell`) was recently discovered impacting PHP runtimes, requiring an immediate upgrade to the patched PHP 8.5.12 release. Additionally, high-severity vulnerabilities affecting Node.js (including out-of-bounds writes in Brotli decoding and DNS/TLS handling) require upgrading Node.js to the latest secure LTS release (v24.22.1) to ensure local development environments remain secure against potential remote exploits.

## What Changes

- Update PHP runtime version definition in `runtimes/manifest.sh` from `8.5.11` to `8.5.12`, updating the binary file name, download URL, and integrity SHA-256 checksum.
- Update Node.js official LTS version in `versions.sh` from `24.21.0` to `24.22.1`.
- Update runtime test assertions in `tests/releases.bats` and related test suites to assert against PHP `8.5.12` and Node.js `24.22.1`.
- Verify that `dev install --plan` and `dev versions` properly report and resolve the upgraded security versions.

## Capabilities

### New Capabilities
<!-- None -->

### Modified Capabilities
- `environment-core`: Update runtime provisioning to enforce patched PHP 8.5.12 (mitigating php2shell) and Node.js 24.22.1 LTS.

## Impact

- **Affected code**: `runtimes/manifest.sh`, `versions.sh`, `tests/releases.bats`.
- **APIs/CLI**: `dev versions` and `dev install --plan` will output the new versions; `url_for` and `cache_name` will construct download URLs pointing to Node.js `v24.22.1` and PHP `8.5.12`.
- **Dependencies**: New tarballs downloaded to `~/.cache/dev` on next `dev install`.
