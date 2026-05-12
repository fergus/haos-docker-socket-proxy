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

### Step 1: Sync with remote and verify repository state

```bash
# Ensure we are on the main branch
git rev-parse --abbrev-ref HEAD
```

Abort with a warning if not on `main`.

```bash
# Ensure working tree is clean
git diff --quiet && git diff --cached --quiet
```

If there are uncommitted changes, stash them or abort and warn the user.

```bash
git pull
```

### Step 2: Check all dependencies

Run the automated checker script first:

```bash
./scripts/check-updates.sh
```

This script extracts current pins and queries remote APIs / Docker for latest versions. It exits non-zero when updates are available and prints a summary table.

If the script is missing or a check fails, fall back to the manual checks below.

#### Manual fallback checks

**2a. HA base image**

Current tag (extract with):
```bash
grep -oP 'amd64-base:\K[0-9.]+' socket-proxy/build.yaml
```

Latest: use `FetchURL` on `https://github.com/home-assistant/docker-base/pkgs/container/amd64-base` or query Alpine Docker Hub as a proxy:
```bash
curl -s "https://hub.docker.com/v2/repositories/library/alpine/tags/?name=3.&page_size=20" | jq -r '.results[].name' | grep -E '^3\.[0-9]+$' | sort -V | tail -1
```

**2b. HAProxy version**

Current pin (extract with):
```bash
grep -oP 'haproxy=\K[0-9.r-]+' socket-proxy/Dockerfile
```

Latest in the current base image:
```bash
docker run --rm ghcr.io/home-assistant/amd64-base:<TAG> sh -c "apk update >/dev/null 2>&1 && apk list -a haproxy" | grep -oP 'haproxy-\K[0-9.r-]+' | head -1
```

> If Docker is unavailable, skip this check and note it in the report.

**2c. Upstream LinuxServer**

Current pin (extract with):
```bash
grep -oP 'UPSTREAM_PIN="linuxserver/docker-socket-proxy:\K[^"]+' socket-proxy/rootfs/etc/services.d/socket-proxy/run
```

Latest release: use `FetchURL` on `https://github.com/linuxserver/docker-socket-proxy/releases/latest` (redirects to the latest release page) or:
```bash
curl -s "https://api.github.com/repos/linuxserver/docker-socket-proxy/releases/latest" | jq -r '.tag_name'
```

**2d. Pre-commit hooks**

```bash
pre-commit autoupdate --dry-run 2>&1 || echo "pre-commit not available"
```

**2e. GitHub Actions versions**

Current pins (extract with):
```bash
grep -oP 'uses:[[:space:]]+\K[^@]+@[^[:space:]]+' .github/workflows/ci.yaml | sort -u
```

For each unique `owner/repo@vN`, use `FetchURL` on `https://github.com/{owner}/{repo}/releases/latest` or:
```bash
curl -s "https://api.github.com/repos/{owner}/{repo}/releases/latest" | jq -r '.tag_name'
```

Only flag an update when the **major version** changes (e.g. `v5` → `v6`).

### Step 3: Report findings

Present a markdown summary table:

| Dependency | Current | Latest | Update needed? |
|---|---|---|---|
| HA base image | 3.23 | ... | ... |
| HAProxy | 3.2.15-r0 | ... | ... |
| Upstream LS | 3.2.15-r0-ls75 | ... | ... |
| Pre-commit hooks | ... | ... | ... |
| actions/checkout | v6 | ... | ... |
| actions/setup-python | v6 | ... | ... |

**If nothing needs updating, stop here and inform the user.**

### Step 4: Update code (if updates found)

Update files per dependency type. Always read each file before editing.

#### HA base image update
- `socket-proxy/build.yaml` — both `aarch64` and `amd64` entries
- `Makefile` — `BUILD_FROM` in the `build` target
- `tests/test_addon.sh` — the `docker build` command in the "Docker build" section

#### HAProxy update
- `socket-proxy/Dockerfile` — the `apk add --no-cache haproxy=` line

#### Upstream LinuxServer update
- `socket-proxy/build.yaml` — line 1 comment
- `socket-proxy/rootfs/etc/services.d/socket-proxy/run` — `UPSTREAM_PIN` variable
- `socket-proxy/rootfs/templates/haproxy.cfg` — fetch the upstream file from `https://raw.githubusercontent.com/linuxserver/docker-socket-proxy/main/root/templates/haproxy.cfg` (note: path changed from `root/defaults/` to `root/templates/`) and diff against the local copy. Do **not** blindly replace the local copy — this project adds custom `@@ALLOWED_SRC_ACL@@` and `@@ALLOWED_SRC_REJECT@@` placeholders and an attribution header that upstream does not have. Only adopt new upstream ACL endpoint rules or other structural changes, preserving the local additions.
- If upstream added new ACL endpoints, also update these files per the consistency requirements in `AGENTS.md`:
  - `socket-proxy/config.yaml` — new schema entry with default value
  - `socket-proxy/rootfs/etc/services.d/socket-proxy/run` — bashio read + env var export
  - `socket-proxy/translations/en.yaml` — UI label and description

#### Pre-commit hooks update
```bash
pre-commit autoupdate
```

#### GitHub Actions update
Edit `.github/workflows/ci.yaml` to update any pinned action versions to their latest major version. Version pins use the `@vN` major-version tag format — only update when a newer major version is available.

### Step 5: Bump version

Determine bump type:
- **Patch** — dependency-only updates (base image, HAProxy pin, pre-commit hooks, GitHub Actions)
- **Minor** — upstream LinuxServer update that adds new features/endpoints
- **Major** — breaking changes (rare for this add-on)

Update these files (read each first):
1. `socket-proxy/config.yaml` — `version` field (line 6)
2. `socket-proxy/rootfs/etc/services.d/socket-proxy/run` — `ADDON_VERSION` variable (keep in sync with config.yaml)
3. `socket-proxy/CHANGELOG.md` — add new version entry at the top, below the `# Changelog` heading. Follow the existing format:

```markdown
## X.Y.Z

- Bump HAProxy from A.B.C-rX to D.E.F-rY
- Bump upstream reference to linuxserver/docker-socket-proxy D.E.F-rY-lsZ
- Update pre-commit hooks: ...
- Update GitHub Actions: ...
```

### Step 6: Verify

Run the full verification suite sequentially:

```bash
make lint
```

```bash
make test
```

```bash
make build
```

If any step fails, diagnose and fix before proceeding. Do not commit broken changes.

### Step 7: Commit and push

Stage changed files explicitly (never use `git add -A` or `git add .`). Use `git status` to see which files were actually modified, then stage only those:

```bash
git add socket-proxy/Dockerfile socket-proxy/build.yaml socket-proxy/config.yaml \
  socket-proxy/CHANGELOG.md socket-proxy/rootfs/etc/services.d/socket-proxy/run \
  socket-proxy/rootfs/templates/haproxy.cfg \
  .pre-commit-config.yaml socket-proxy/translations/en.yaml \
  .github/workflows/ci.yaml
```

Only stage files that were actually modified. Verify with:

```bash
git diff --cached --name-only
```

If no files are staged, stop and inform the user.

Commit with a descriptive message summarizing what was updated. Make no reference to Claude, Anthropic, or AI in the commit message. Example formats:

```
Bump HAProxy to 3.2.18-r0 and upstream to ls81
```

```
Bump base image to Alpine 3.24 and HAProxy to 3.2.17-r0
```

Then push only if there is a commit to push:

```bash
git push
```
