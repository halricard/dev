# Design

## Context

The dev environment manages precompiled runtimes for PHP and Node.js:
- PHP static runtime metadata is declared in `runtimes/manifest.sh` (`PHP_RUNTIME_VERSION`, `PHP_RUNTIME_FILE`, `PHP_RUNTIME_SHA256`).
- Node.js LTS version is pinned in `versions.sh` (`NODE_VERSION`).
- Dynamic download URL generation, archive caching, and version inspection commands (`dev versions`, `dev install --plan`) read these constants through `lib/releases.sh`.
- Test suites in `tests/releases.bats` validate pinned and dynamic runtime version output.

See `proposal.md` for vulnerability motivation (`php2shell` and Node.js security disclosures).

## Goals / Non-Goals

**Goals:**
- Upgrade PHP runtime to `8.5.12` with updated manifest file paths and SHA-256 checksum.
- Upgrade Node.js official LTS to `24.22.1` to incorporate security patches for critical buffer overflow and network flaws.
- Update test suite assertions and ensure compatibility across `dev versions`, `dev install --plan`, and `tools/check.sh`.

**Non-Goals:**
- Upgrading to Node.js 26.x (avoiding major version breaks; preserving Node 24.x LTS series).
- Changing MySQL, Nginx, Mailpit, Composer, or Adminer pinned versions.
- Altering the static compilation extension set or GLIBC minimum version requirements.

## Decisions

### Decision 1: Target Node.js 24.22.1 LTS
- **Rationale**: The dev environment is standardized on the Node 24.x LTS release line (`24.21.0`). Version `24.22.1` delivers the security fixes (specifically addressing out-of-bounds writes in Brotli and DNS/TLS issues) without introducing major breaking API changes.
- **Alternatives considered**:
  - Node 26.x: Newer release line, but risks breaking existing user scripts and dependencies expecting 24.x LTS.
  - Node 22.x: Maintenance LTS, but represents a regression from 24.x.

### Decision 2: Preserve PHP Manifest Extension Architecture
- **Rationale**: PHP 8.5.12 is a point security release addressing the `php2shell` vulnerability. The required static extension set (`bcmath`, `curl`, `mbstring`, `pdo_mysql`, etc.) and GLIBC requirement (`2.38`) remain completely unchanged from 8.5.11.
- **Alternatives considered**: None; patch release preserves existing binary contract.

### Decision 3: Versioned Cache Artifact Isolation
- **Rationale**: `cache_name` in `lib/releases.sh` automatically incorporates the version string into file names (`php-8.5.12-linux-x86_64.tar.xz` and `node-v24.22.1-linux-x64.tar.xz`). This isolates new downloads in `~/.cache/dev` without polluting or conflicting with previously cached 8.5.11 / 24.21.0 archives.

## Risks / Trade-offs

- **[Risk] Test suite breakages due to hardcoded version assertions**  
  → *Mitigation*: Update `tests/releases.bats` alongside the manifest changes and run Bats test suite via `tools/test.sh`.
- **[Risk] Checksum mismatch if PHP binary archive is updated**  
  → *Mitigation*: Specify valid SHA-256 hash matching the 8.5.12 release archive in `runtimes/manifest.sh`.

## Migration Plan

1. Update `runtimes/manifest.sh` (`PHP_RUNTIME_VERSION`, `PHP_RUNTIME_FILE`, `PHP_RUNTIME_SHA256`).
2. Update `versions.sh` (`NODE_VERSION`).
3. Update `tests/releases.bats` assertions.
4. Run `tools/check.sh` and `tools/test.sh` to confirm syntax, linter, and Bats test pass.
5. Rollback strategy: Revert git commits on `runtimes/manifest.sh`, `versions.sh`, and `tests/releases.bats`.
