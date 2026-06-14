# AGENTS.md — Docker Socket Proxy (Home Assistant Add-on)

> File intended for AI coding agents. Read this first before modifying anything in this repository.

---

## Project Overview

This repository is a **Home Assistant Add-on** (not a standalone application). It packages a filtered, read-only Docker socket proxy for Home Assistant OS (HAOS), allowing remote tools like Dozzle to monitor HAOS containers without exposing the full Docker socket.

The add-on is based on the [LinuxServer docker-socket-proxy](https://github.com/linuxserver/docker-socket-proxy) approach, adapted to Home Assistant OS conventions. It runs an HAProxy instance inside an Alpine Linux container. HAProxy acts as a reverse proxy to the host's Docker Unix socket, with per-endpoint ACL rules that allow or deny API paths based on user-configurable toggles.

- **Repository URL:** https://github.com/fergus/haos-docker-socket-proxy
- **Add-on slug:** `socket-proxy`
- **License:** GPL-3.0-or-later
- **Current version:** 1.2.3
- **Supported architectures:** `amd64`, `aarch64`

---

## Technology Stack

| Layer | Technology |
|-------|------------|
| Base image | `ghcr.io/home-assistant/{amd64,aarch64}-base:3.23` (Alpine Linux) |
| Proxy | HAProxy 3.2.19-r0 (pinned Alpine package) |
| Service supervision | s6-overlay (provided by HA base image) |
| Shell helpers | `bashio` (Home Assistant bash helper library) |
| Config / metadata | YAML (`config.yaml`, `build.yaml`, `translations/en.yaml`) |
| CI/CD | GitHub Actions |
| Linting | pre-commit (yamllint, shellcheck, hadolint, trailing-whitespace, etc.) |

There is **no** `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, or similar language-specific package manifest. All runtime dependencies are installed via Alpine `apk` in the Dockerfile.

---

## Directory Structure

```
.
├── .github/workflows/ci.yaml       # GitHub Actions CI pipeline
├── .pre-commit-config.yaml         # pre-commit hooks configuration
├── .yamllint.yaml                  # yamllint rules
├── Makefile                        # Developer convenience targets
├── README.md                       # Human-facing repository README
├── repository.yaml                 # HA add-on repository metadata
├── socket-proxy/                   # Add-on directory (single add-on in this repo)
│   ├── CHANGELOG.md                # Version history
│   ├── DOCS.md                     # Add-on documentation (shown in HA UI)
│   ├── Dockerfile                  # Container build — installs haproxy
│   ├── README.md                   # Store-facing README
│   ├── build.yaml                  # Multi-arch base image pins + OCI labels
│   ├── config.yaml                 # Add-on manifest: options, schema, ports, permissions
│   ├── icon.png / icon.svg / logo.png
│   ├── translations/
│   │   └── en.yaml                 # UI labels + descriptions for each config option
│   └── rootfs/                     # Files copied into container root (see Dockerfile: COPY rootfs /)
│       ├── templates/haproxy.cfg   # HAProxy config template with @@placeholders@@
│       └── etc/services.d/socket-proxy/
│           ├── finish              # s6 finish script (execlineb)
│           └── run                 # s6 run script (bash) — main entrypoint
└── tests/
    └── test_addon.sh               # Comprehensive bash test suite
```

---

## Runtime Architecture

1. **Container startup:** The Home Assistant Supervisor starts the container with `docker_api: true` in `config.yaml`, which mounts the host Docker socket into the container.
2. **s6 service supervision:** The HA base image uses s6-overlay. The `run` script at `/etc/services.d/socket-proxy/run` is executed automatically.
3. **Configuration phase (`run` script):**
   - Reads user options via `bashio::config`.
   - Converts boolean toggles to `0`/`1` environment variables.
   - Validates `ALLOWED_CIDRS` entries with a regex-based `is_valid_cidr` function.
   - Renders `/templates/haproxy.cfg` into `/run/haproxy/haproxy.cfg` by substituting `@@BIND_PROTO@@`, `@@ALLOWED_SRC_ACL@@`, and `@@ALLOWED_SRC_REJECT@@`.
   - Writes valid CIDRs to `/run/haproxy/allowed_ips.acl`.
4. **Proxy runtime:** `exec haproxy -f /run/haproxy/haproxy.cfg -W -db`
   - **Frontend (`proxy`):** Listens on the configured port. Applies source-IP ACLs, then allows/denies Docker API paths based on env-driven boolean checks (`env(CONTAINERS) -m bool`, etc.). Only `GET` is permitted unless `POST` or a specific write toggle is enabled.
   - **Backend (`docker`):** Forwards allowed requests to `$SOCKET_PATH` (the host Docker socket).
5. **Finish script:** If the service exits with a non-zero, non-256 code, s6 shuts down the entire container supervision tree.

**Important:** The add-on requires **Protection mode to be disabled** in the Home Assistant UI. Without this, the Docker socket is not mounted and the add-on fails to start.

---

## Build and Test Commands

All development commands are wrapped in the `Makefile`:

```bash
make setup    # Install pre-commit and register git hooks
make lint     # Run all pre-commit hooks on all files
make test     # Run tests/test_addon.sh
make build    # Docker build the add-on image locally
make all      # lint + test + build (default target)
make clean    # Remove local test image
```

### Prerequisites

- Python 3 (for YAML validation and config consistency checks in the test suite)
- Docker (for the Docker build test)
- `pre-commit` (Python package, installed via `make setup`)
- Optional but recommended: `shellcheck`, `hadolint` (the test suite skips their checks if missing)

---

## Code Style Guidelines

### Licensing

Every source file **must** begin with the project banner and SPDX identifier:

```
# Docker Socket Proxy - Home Assistant add-on
# Copyright (C) 2025 Fergus Stevens
#
# SPDX-License-Identifier: GPL-3.0-or-later
```

### Shell Scripts

- `run` script: `#!/usr/bin/with-contenv bashio` (not plain `#!/bin/bash`). This is required to access `bashio` helpers and s6 environment.
- `finish` script: `#!/usr/bin/execlineb -S1` — this is execlineb, not bash. Do not change this.
- Follow `shellcheck` severity=warning rules.
- In the `run` script, always add `# shellcheck shell=bash` after the shebang.

### YAML

- Document-start (`---`) is **disabled** per `.yamllint.yaml`.
- Line length warning at 200 chars.
- `truthy.check-keys: false` allows `on:` in GitHub Actions workflow keys.

### Dockerfile

- Pin package versions exactly: `apk add --no-cache haproxy=3.2.19-r0`.
- `BUILD_FROM` is passed as a build arg (set by the Home Assistant builder or CI).

---

## Testing Strategy

The test suite (`tests/test_addon.sh`) is a single bash script with no external test framework. It runs several sections:

1. **Structural checks:** Verifies that required files exist and that `run`/`finish` are executable.
2. **YAML validity:** Uses Python `PyYAML` to parse `config.yaml`, `build.yaml`, `translations/en.yaml`, and `repository.yaml`.
3. **ShellCheck:** Runs `shellcheck --severity=warning --shell=bash` on the `run` script.
4. **Hadolint:** Lints the `Dockerfile`.
5. **Config consistency (Python-driven):**
   - Every option in `config.yaml`'s `options` block has a translation in `translations/en.yaml`.
   - Every option has a matching `schema` entry in `config.yaml`.
   - Every `bool` schema option is referenced in the `run` script (prevents stale toggles).
   - Architectures in `config.yaml` match architectures in `build.yaml`.
   - Version follows strict semver (`X.Y.Z`).
6. **CIDR validation:** Unit-tests the `is_valid_cidr` function extracted from the `run` script against valid and invalid IPv4/IPv6 addresses and CIDRs.
7. **Template rendering:** Renders `haproxy.cfg` with sed substitutions and asserts presence/absence of ACL lines for empty vs. non-empty allowlists.
8. **Docker build:** Builds the image locally.

The script reports `PASS`/`FAIL`/`SKIP` counts and exits non-zero if any test fails.

---

## Security Considerations

- **Privileged access:** The add-on sets `docker_api: true`, `full_access: true`, and `protected: false` in `config.yaml`. It is explicitly unprotected because it needs the Docker socket.
- **Read-only by default:** Only `GET` requests are allowed. Write operations require explicit opt-in via `POST` or granular toggles (`ALLOW_START`, `ALLOW_STOP`, `ALLOW_RESTARTS`, `ALLOW_PAUSE`, `ALLOW_UNPAUSE`).
- **Source-IP filtering:** `ALLOWED_CIDRS` rejects connections at the TCP layer before any API processing. Empty list = allow all.
- **IPv6 caveat:** When `DISABLE_IPV6` is off (dual-stack), HAProxy sees IPv4 clients as IPv4-mapped IPv6 (`::ffff:...`). Plain IPv4 CIDRs will **not** match. The default is `DISABLE_IPV6: true` to avoid this footgun.
- **No authentication:** The proxy does not implement TLS or HTTP authentication. Security relies on network segmentation and source-IP restrictions.

---

## Development Conventions

### Adding a New API Endpoint Toggle

If a new Docker API endpoint needs to be exposed, you must update **all** of the following to keep the test suite passing:

1. `socket-proxy/config.yaml`:
   - Add the option to `options:` with a default (`true` or `false`).
   - Add the matching type to `schema:` (usually `bool`).
2. `socket-proxy/translations/en.yaml`:
   - Add a `configuration.<OPTION>` entry with `name:` and `description:`.
3. `socket-proxy/rootfs/etc/services.d/socket-proxy/run`:
   - Read the option with `bashio::config` (or `bashio::config.true` for booleans).
   - Export the environment variable.
   - Add the variable to the `ENABLED` loop or relevant write-ops logic.
4. `socket-proxy/rootfs/templates/haproxy.cfg`:
   - Add an `http-request allow` rule for the new endpoint, gated on the env variable.

### Version Bumping

When releasing, update **both**:

- `socket-proxy/config.yaml` — `version:` field
- `socket-proxy/rootfs/etc/services.d/socket-proxy/run` — `ADDON_VERSION` variable

Then prepend a new section to `socket-proxy/CHANGELOG.md`.

### Dependency Pinning

All runtime and tooling dependencies are pinned:

- HAProxy package version in `Dockerfile`
- Base image tags in `build.yaml` (per architecture)
- Upstream LinuxServer reference in `build.yaml` comment and `run` script's `UPSTREAM_PIN`
- pre-commit hook revisions in `.pre-commit-config.yaml`
- GitHub Actions versions in `.github/workflows/ci.yaml`

There is a project skill at `.claude/skills/fs-update/SKILL.md` that documents the full workflow for checking and updating these pins.

---

## CI/CD

The GitHub Actions workflow (`.github/workflows/ci.yaml`) runs three sequential jobs:

1. **lint** — `pre-commit run --all-files`
2. **test** — `./tests/test_addon.sh` (requires `pyyaml`)
3. **build** — `docker build` with the amd64 base image tag pinned in `build.yaml`

All jobs run on `ubuntu-latest`. The workflow triggers on pushes and pull requests to `main`.

---

## Common Pitfalls

- **Do not** change the `finish` script to bash — it is execlineb and runs under s6.
- **Do not** forget to add new `bool` options to the `run` script; the test suite will fail them as "unreferenced".
- **Do not** use `git add -A` when committing version bumps or dependency updates. Stage files explicitly (see the `fs-update` skill).
- **Do not** assume `python3` or `docker` are available in all environments — the test suite gracefully skips checks when tools are missing.
