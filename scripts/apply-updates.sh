#!/usr/bin/env bash
# Docker Socket Proxy - Home Assistant add-on
# Copyright (C) 2025 Fergus Stevens
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Apply available dependency updates in-place.
# Must be run from the project root (or will cd there automatically).
# Exit 0 if changes were applied, 1 if nothing to update.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info() { echo "==> $*"; }
ok()   { echo "✓ $*"; }
err()  { echo "✗ $*" >&2; }

grep_extract() {
    local file="$1" pattern="$2" fallback="${3:-unknown}"
    grep -oP "$pattern" "$file" 2>/dev/null | head -1 || echo "$fallback"
}

# Returns 0 (true) if $1 < $2 in semver order (ignores -rN and -lsN suffixes)
version_lt() {
    local a="${1%-r*}" b="${2%-r*}"
    a="${a%-ls*}" b="${b%-ls*}"
    [[ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -1)" == "$a" && "$a" != "$b" ]]
}

bump_patch() {
    local major minor patch
    IFS='.' read -r major minor patch <<< "$1"
    echo "${major}.${minor}.$((patch + 1))"
}

CHANGELOG_FILE="socket-proxy/CHANGELOG.md"

# write_changelog <version> <entry>...
# Inserts a new "## <version>" section above the newest existing one, so the
# file stays newest-first. The release job in ci.yaml reads this section
# verbatim for the GitHub release notes, so the heading must match the version
# in config.yaml exactly.
write_changelog() {
    local version="$1"
    shift

    if [[ ! -f "$CHANGELOG_FILE" ]]; then
        err "${CHANGELOG_FILE} not found; skipping changelog entry"
        return 0
    fi

    if grep -qxF "## ${version}" "$CHANGELOG_FILE"; then
        err "Changelog already has a section for ${version}; leaving it untouched"
        return 0
    fi

    local section
    section="$(mktemp)"
    {
        printf '## %s\n\n' "$version"
        printf -- '- %s\n' "$@"
        printf '\n'
    } > "$section"

    awk -v section="$section" '
        !inserted && /^## / {
            while ((getline line < section) > 0) print line
            close(section)
            inserted = 1
        }
        { print }
        END {
            # No existing release sections (fresh changelog): append instead.
            if (!inserted) {
                while ((getline line < section) > 0) print line
                close(section)
            }
        }
    ' "$CHANGELOG_FILE" > "${CHANGELOG_FILE}.tmp"

    mv "${CHANGELOG_FILE}.tmp" "$CHANGELOG_FILE"
    rm -f "$section"
    info "Added CHANGELOG.md entry for ${version}"
}

# ---------------------------------------------------------------------------
# Read current pins from source files
# ---------------------------------------------------------------------------

BASE_IMAGE_TAG=$(grep_extract socket-proxy/build.yaml 'amd64-base:\K[0-9.]+' 'unknown')
HAPROXY_PIN=$(grep_extract socket-proxy/Dockerfile 'haproxy=\K[0-9.r-]+' 'unknown')
UPSTREAM_PIN=$(grep_extract socket-proxy/rootfs/etc/services.d/socket-proxy/run 'UPSTREAM_PIN="linuxserver/docker-socket-proxy:\K[^"]+' 'unknown')
ADDON_VERSION=$(grep_extract socket-proxy/config.yaml '^version: \K[0-9.]+' 'unknown')

echo ""
echo "Current pins:"
echo "  Add-on version : ${ADDON_VERSION}"
echo "  HA base image  : ${BASE_IMAGE_TAG}"
echo "  HAProxy        : ${HAPROXY_PIN}"
echo "  Upstream LS    : ${UPSTREAM_PIN}"
echo ""

# ---------------------------------------------------------------------------
# Detect latest versions
# ---------------------------------------------------------------------------

# 1. HA base image — probe GHCR for newer minor tags
info "Checking latest HA base image..."
BASE_IMAGE_LATEST="$BASE_IMAGE_TAG"
if command -v docker >/dev/null 2>&1; then
    _major="${BASE_IMAGE_TAG%%.*}"
    _minor="${BASE_IMAGE_TAG##*.}"
    for _i in $(seq 1 5); do
        _candidate="${_major}.$((${_minor} + ${_i}))"
        if docker manifest inspect "ghcr.io/home-assistant/amd64-base:${_candidate}" >/dev/null 2>&1; then
            BASE_IMAGE_LATEST="$_candidate"
        else
            break
        fi
    done
else
    err "Docker not available; cannot check HA base image"
fi

# 2. HAProxy — query apk inside the (potentially updated) base image
info "Checking latest HAProxy in base image ${BASE_IMAGE_LATEST}..."
HAPROXY_LATEST="$HAPROXY_PIN"
if command -v docker >/dev/null 2>&1; then
    HAPROXY_LATEST=$(docker run --rm \
        "ghcr.io/home-assistant/amd64-base:${BASE_IMAGE_LATEST}" \
        sh -c "apk update >/dev/null 2>&1 && apk list -a haproxy" 2>/dev/null \
        | grep -oP 'haproxy-\K[0-9.r-]+' | head -1 || echo "$HAPROXY_PIN")
else
    err "Docker not available; cannot check HAProxy version"
fi

# 3. Upstream LinuxServer docker-socket-proxy
info "Checking latest LinuxServer docker-socket-proxy release..."
UPSTREAM_LATEST="$UPSTREAM_PIN"
if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    _tag=$(curl -sfL "https://api.github.com/repos/linuxserver/docker-socket-proxy/releases/latest" \
        | jq -r '.tag_name // empty')
    [[ -n "$_tag" ]] && UPSTREAM_LATEST="$_tag"
else
    err "curl/jq not available; cannot check upstream version"
fi

# 4. GitHub Actions versions
declare -A GHA_CURRENT GHA_LATEST

while IFS= read -r line; do
    if [[ "$line" =~ uses:[[:space:]]+([^@]+)@(v[0-9]+) ]]; then
        action="${BASH_REMATCH[1]}"
        current="${BASH_REMATCH[2]}"
        [[ -n "${GHA_CURRENT[$action]:-}" ]] && continue
        GHA_CURRENT[$action]="$current"
        GHA_LATEST[$action]="$current"
        if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
            _latest=$(curl -sfL "https://api.github.com/repos/${action}/releases/latest" \
                | jq -r '.tag_name // empty' | grep -oP '^v\K[0-9]+' | head -1 || true)
            [[ -n "$_latest" ]] && GHA_LATEST[$action]="v${_latest}"
        fi
    fi
done < .github/workflows/ci.yaml

# ---------------------------------------------------------------------------
# Apply changes
# ---------------------------------------------------------------------------

CHANGED=0
CHANGELOG_LINES=()

# HA base image
if version_lt "$BASE_IMAGE_TAG" "$BASE_IMAGE_LATEST"; then
    info "Updating HA base image: ${BASE_IMAGE_TAG} → ${BASE_IMAGE_LATEST}"
    # The base image tag appears in every file that builds or documents the
    # image. Missing one (notably ci.yaml) makes CI build against the old
    # Alpine release, where the new haproxy package does not exist.
    sed -i \
        "s|aarch64-base:${BASE_IMAGE_TAG}|aarch64-base:${BASE_IMAGE_LATEST}|g;
         s|amd64-base:${BASE_IMAGE_TAG}|amd64-base:${BASE_IMAGE_LATEST}|g" \
        socket-proxy/build.yaml \
        .github/workflows/ci.yaml \
        Makefile \
        tests/test_addon.sh \
        AGENTS.md
    CHANGELOG_LINES+=("Bump HA base image from Alpine ${BASE_IMAGE_TAG} to ${BASE_IMAGE_LATEST}")
    CHANGED=1
else
    ok "HA base image up to date (${BASE_IMAGE_TAG})"
fi

# HAProxy
if version_lt "$HAPROXY_PIN" "$HAPROXY_LATEST"; then
    info "Updating HAProxy: ${HAPROXY_PIN} → ${HAPROXY_LATEST}"
    sed -i "s|haproxy=${HAPROXY_PIN}|haproxy=${HAPROXY_LATEST}|" socket-proxy/Dockerfile
    CHANGELOG_LINES+=("Bump HAProxy from ${HAPROXY_PIN} to ${HAPROXY_LATEST} (Alpine ${BASE_IMAGE_LATEST} package update)")
    CHANGED=1
else
    ok "HAProxy up to date (${HAPROXY_PIN})"
fi

# Upstream LS pin (build.yaml comment + run script)
if version_lt "$UPSTREAM_PIN" "$UPSTREAM_LATEST"; then
    info "Updating upstream LS: ${UPSTREAM_PIN} → ${UPSTREAM_LATEST}"
    sed -i "s|linuxserver/docker-socket-proxy:${UPSTREAM_PIN}|linuxserver/docker-socket-proxy:${UPSTREAM_LATEST}|g" \
        socket-proxy/build.yaml \
        socket-proxy/rootfs/etc/services.d/socket-proxy/run
    CHANGELOG_LINES+=("Bump upstream reference to linuxserver/docker-socket-proxy ${UPSTREAM_LATEST}")
    CHANGED=1
else
    ok "Upstream LS up to date (${UPSTREAM_PIN})"
fi

# GitHub Actions (major version bumps only)
for action in $(printf '%s\n' "${!GHA_CURRENT[@]}" | sort); do
    current="${GHA_CURRENT[$action]}"
    latest="${GHA_LATEST[$action]}"
    if [[ "$current" != "$latest" ]]; then
        info "Updating GHA ${action}: ${current} → ${latest}"
        sed -i "s|uses: ${action}@${current}|uses: ${action}@${latest}|g" .github/workflows/ci.yaml
        CHANGELOG_LINES+=("Update GitHub Actions: ${action} ${current} to ${latest}")
        CHANGED=1
    else
        ok "GHA ${action} up to date (${current})"
    fi
done

# Version bump + propagate to run script
if [[ "$CHANGED" -eq 1 ]]; then
    NEW_VERSION=$(bump_patch "$ADDON_VERSION")
    info "Bumping version: ${ADDON_VERSION} → ${NEW_VERSION}"
    sed -i "s|^version: ${ADDON_VERSION}|version: ${NEW_VERSION}|" socket-proxy/config.yaml
    sed -i "s|ADDON_VERSION=\"${ADDON_VERSION}\"|ADDON_VERSION=\"${NEW_VERSION}\"|" \
        socket-proxy/rootfs/etc/services.d/socket-proxy/run
    write_changelog "$NEW_VERSION" "${CHANGELOG_LINES[@]}"
    echo ""
    ok "All updates applied. New add-on version: ${NEW_VERSION}"
    exit 0
else
    echo ""
    ok "Nothing to update."
    exit 1
fi
