---
name: fs-update
description: Check and update all pinned dependencies for the HA Docker Socket Proxy add-on
disable-model-invocation: true
---

# fs-update

Check and update all pinned dependencies for the HA Docker Socket Proxy add-on.

## Trigger

User invokes `/fs-update`.

## Workflow

### Step 1: Sync with remote

```bash
git pull
```

### Step 2: Check all dependencies (run in parallel)

#### 2a. HA base image

Read the current base image tag from `socket-proxy/build.yaml`. Then check for the latest available tag:

```bash
# Check what's available — look at the GitHub container registry
```

Use `WebFetch` to check `https://github.com/home-assistant/docker-base/pkgs/container/amd64-base` for the latest tag. Compare to the current pin in `socket-proxy/build.yaml`.

#### 2b. HAProxy version

Check what HAProxy version is available in the **current** (and if changed, the **new**) base image:

```bash
docker run --rm ghcr.io/home-assistant/amd64-base:<TAG> sh -c "apk update >/dev/null 2>&1 && apk list -a haproxy"
```

Compare to the pin in `socket-proxy/Dockerfile` (the `apk add --no-cache haproxy=X.X.X` line).

If the base image is being updated, re-check HAProxy availability in the new image.

#### 2c. Upstream LinuxServer

Use `WebFetch` to check `https://github.com/linuxserver/docker-socket-proxy/releases` for the latest release tag. Compare to:
- The comment in `socket-proxy/build.yaml` line 1
- The `UPSTREAM_PIN` variable in `socket-proxy/rootfs/etc/services.d/socket-proxy/run`

#### 2d. Pre-commit hooks

```bash
cd /home/ferg/code/ha_app_socket_proxy && pre-commit autoupdate --dry-run 2>&1 || echo "pre-commit not available"
```

#### 2e. GitHub Actions versions

Read `.github/workflows/ci.yaml` and note every pinned action (e.g. `actions/checkout@v4`, `actions/setup-python@v5`). For each action, use `WebFetch` to check the latest major version tag on GitHub (e.g. `https://github.com/actions/checkout/releases/latest` and `https://github.com/actions/setup-python/releases/latest`). Compare to the versions pinned in the workflow file.

### Step 3: Report findings

Present a markdown summary table:

| Dependency | Current | Latest | Update needed? |
|---|---|---|---|
| HA base image | 3.23 | ... | ... |
| HAProxy | 3.2.13-r0 | ... | ... |
| Upstream LS | 3.2.13-r0-ls70 | ... | ... |
| Pre-commit hooks | ... | ... | ... |
| actions/checkout | v4 | ... | ... |
| actions/setup-python | v5 | ... | ... |

**If nothing needs updating, stop here and inform the user.**

### Step 4: Update code (if updates found)

Update files per dependency type. Always read each file before editing.

#### HA base image update
- `socket-proxy/build.yaml` — both `aarch64` and `amd64` entries
- `CLAUDE.md` — version pins section and any build commands referencing the tag
- `/home/ferg/.claude/projects/-home-ferg-code-ha-app-socket_proxy/memory/MEMORY.md` — version pins

#### HAProxy update
- `socket-proxy/Dockerfile` — the `apk add --no-cache haproxy=` line
- `CLAUDE.md` — version pins section
- `/home/ferg/.claude/projects/-home-ferg-code-ha-app-socket-proxy/memory/MEMORY.md` — version pins

#### Upstream LinuxServer update
- `socket-proxy/build.yaml` — line 1 comment
- `socket-proxy/rootfs/etc/services.d/socket-proxy/run` — `UPSTREAM_PIN` variable
- `socket-proxy/rootfs/templates/haproxy.cfg` — fetch the upstream file from `https://raw.githubusercontent.com/linuxserver/docker-socket-proxy/main/root/defaults/haproxy.cfg` and diff against the local copy. If changed, replace the local copy entirely.
- If upstream added new ACL endpoints, also update these files per the consistency requirements in CLAUDE.md:
  - `socket-proxy/config.yaml` — new schema entry with default value
  - `socket-proxy/rootfs/etc/services.d/socket-proxy/run` — bashio read + env var export
  - `socket-proxy/translations/en.yaml` — UI label and description
- `CLAUDE.md` — upstream reference

#### Pre-commit hooks update
```bash
cd /home/ferg/code/ha_app_socket_proxy && pre-commit autoupdate
```

#### GitHub Actions update
Edit `.github/workflows/ci.yaml` to update any pinned action versions to their latest major version. Version pins use the `@vN` major-version tag format — only update when a newer major version is available.

### Step 5: Bump version

Determine bump type:
- **Patch** — dependency-only updates (base image, HAProxy pin, pre-commit hooks)
- **Minor** — upstream LinuxServer update that adds new features/endpoints

Update these files (read each first):
1. `socket-proxy/config.yaml` — `version` field (line 6)
2. `socket-proxy/rootfs/etc/services.d/socket-proxy/run` — `ADDON_VERSION` variable (keep in sync with config.yaml)
3. `socket-proxy/CHANGELOG.md` — add new version entry at the top, below the `# Changelog` heading

### Step 6: Verify

Run tests and build sequentially:

```bash
cd /home/ferg/code/ha_app_socket_proxy && make test
```

```bash
cd /home/ferg/code/ha_app_socket_proxy && make build
```

If either fails, diagnose and fix before proceeding.

### Step 7: Commit and push

Stage changed files explicitly (never use `git add -A` or `git add .`):

```bash
git add socket-proxy/Dockerfile socket-proxy/build.yaml socket-proxy/config.yaml \
  socket-proxy/CHANGELOG.md socket-proxy/rootfs/etc/services.d/socket-proxy/run \
  socket-proxy/rootfs/templates/haproxy.cfg CLAUDE.md \
  .pre-commit-config.yaml socket-proxy/translations/en.yaml \
  .github/workflows/ci.yaml
```

Only stage files that were actually modified. Use `git status` to confirm.

Commit with a descriptive message summarizing what was updated. Make no reference to Claude or Anthropic in the commit message. Example format:

```
Bump HAProxy to X.X.X and base image to Y.Y
```

Then push:

```bash
git push
```
