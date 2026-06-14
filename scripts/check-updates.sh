#!/usr/bin/env bash
# Docker Socket Proxy - Home Assistant add-on
# Copyright (C) 2025 Fergus Stevens
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Dependency update checker
# Usage: ./scripts/check-updates.sh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info()  { echo -e "${BLUE}==>${NC} $*"; }
ok()    { echo -e "${GREEN}✓${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
err()   { echo -e "${RED}✗${NC} $*"; }

# Extract first match via grep -oP, or print fallback
grep_extract() {
    local file="$1" pattern="$2" fallback="${3:-unknown}"
    grep -oP "$pattern" "$file" 2>/dev/null | head -1 || echo "$fallback"
}

# Compare two semver-like strings (ignores -r0 / -ls suffixes for comparison)
# Returns 0 if $1 < $2
version_lt() {
    local a="$1" b="$2"
    # Strip common suffixes for numeric comparison
    a="${a%-r*}"
    b="${b%-r*}"
    a="${a%-ls*}"
    b="${b%-ls*}"
    # Use sort -V
    [[ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -1)" == "$a" && "$a" != "$b" ]]
}

# ---------------------------------------------------------------------------
# Current versions
# ---------------------------------------------------------------------------

info "Reading current dependency pins..."

BASE_IMAGE_TAG=$(grep_extract socket-proxy/build.yaml 'amd64-base:\K[0-9.]+' 'unknown')
HAPROXY_PIN=$(grep_extract socket-proxy/Dockerfile 'haproxy=\K[0-9.r-]+' 'unknown')
UPSTREAM_RUN=$(grep_extract socket-proxy/rootfs/etc/services.d/socket-proxy/run 'UPSTREAM_PIN="linuxserver/docker-socket-proxy:\K[^"]+' 'unknown')
UPSTREAM_BUILD=$(grep_extract socket-proxy/build.yaml 'linuxserver/docker-socket-proxy:\K[^ ]+' 'unknown' | head -1)
ADDON_VERSION=$(grep_extract socket-proxy/config.yaml '^version: \K[0-9.]+' 'unknown')

echo ""
echo -e "  Add-on version:     ${BOLD}${ADDON_VERSION}${NC}"
echo -e "  HA base image:      ${BOLD}${BASE_IMAGE_TAG}${NC}"
echo -e "  HAProxy pin:        ${BOLD}${HAPROXY_PIN}${NC}"
echo -e "  Upstream pin (run): ${BOLD}${UPSTREAM_RUN}${NC}"
echo -e "  Upstream pin (build comment): ${BOLD}${UPSTREAM_BUILD}${NC}"
echo ""

# Consistency check
if [[ "$UPSTREAM_RUN" != "$UPSTREAM_BUILD" ]]; then
    warn "Upstream pins are inconsistent between build.yaml and run script"
fi

# ---------------------------------------------------------------------------
# 1. HA base image (probe actual GHCR tags)
# ---------------------------------------------------------------------------

info "Checking latest HA base image tag (ghcr.io/home-assistant/amd64-base)..."
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
    err "Docker not available; cannot check HA base image version"
    BASE_IMAGE_LATEST="unknown"
fi

if [[ "$BASE_IMAGE_LATEST" == "unknown" ]]; then
    BASE_IMAGE_UPDATE="skip"
elif version_lt "$BASE_IMAGE_TAG" "$BASE_IMAGE_LATEST"; then
    warn "Update available: ${BASE_IMAGE_TAG} → ${BASE_IMAGE_LATEST}"
    BASE_IMAGE_UPDATE="yes"
else
    ok "Up to date (${BASE_IMAGE_TAG})"
    BASE_IMAGE_UPDATE="no"
fi

# ---------------------------------------------------------------------------
# 2. HAProxy version in base image
# ---------------------------------------------------------------------------

# Check against the target base image (latest), not the currently pinned one.
# If the base image is already up to date, these are the same.
_haproxy_check_tag="${BASE_IMAGE_LATEST}"
[[ "$_haproxy_check_tag" == "unknown" ]] && _haproxy_check_tag="$BASE_IMAGE_TAG"

info "Checking HAProxy version available in base image ${_haproxy_check_tag}..."
HAPROXY_LATEST="unknown"
if command -v docker >/dev/null 2>&1; then
    HAPROXY_LATEST=$(docker run --rm "ghcr.io/home-assistant/amd64-base:${_haproxy_check_tag}" sh -c "apk update >/dev/null 2>&1 && apk list -a haproxy" 2>/dev/null | grep -oP 'haproxy-\K[0-9.r-]+' | head -1 || echo "unknown")
else
    err "Docker not available; cannot check HAProxy version in base image"
fi

if [[ "$HAPROXY_LATEST" == "unknown" ]]; then
    err "Could not determine latest HAProxy version"
    HAPROXY_UPDATE="skip"
elif version_lt "$HAPROXY_PIN" "$HAPROXY_LATEST"; then
    warn "Update available: ${HAPROXY_PIN} → ${HAPROXY_LATEST}"
    HAPROXY_UPDATE="yes"
else
    ok "Up to date (${HAPROXY_PIN})"
    HAPROXY_UPDATE="no"
fi

# ---------------------------------------------------------------------------
# 3. Upstream LinuxServer docker-socket-proxy
# ---------------------------------------------------------------------------

info "Checking latest LinuxServer docker-socket-proxy release..."
UPSTREAM_LATEST="unknown"
if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    UPSTREAM_LATEST=$(curl -sfL "https://api.github.com/repos/linuxserver/docker-socket-proxy/releases/latest" 2>/dev/null | jq -r '.tag_name // "unknown"')
fi

if [[ "$UPSTREAM_LATEST" == "unknown" ]]; then
    err "Could not determine latest upstream version (curl/jq unavailable or API failure)"
    UPSTREAM_UPDATE="skip"
elif version_lt "$UPSTREAM_RUN" "$UPSTREAM_LATEST"; then
    warn "Update available: ${UPSTREAM_RUN} → ${UPSTREAM_LATEST}"
    UPSTREAM_UPDATE="yes"
else
    ok "Up to date (${UPSTREAM_RUN})"
    UPSTREAM_UPDATE="no"
fi

# ---------------------------------------------------------------------------
# 4. GitHub Actions versions
# ---------------------------------------------------------------------------

info "Checking GitHub Actions versions..."
declare -A GHA_CURRENT
declare -A GHA_LATEST
declare -A GHA_UPDATE

while IFS= read -r line; do
    # Match lines like "uses: actions/checkout@v6"
    if [[ "$line" =~ uses:[[:space:]]+([^@]+)@(.*) ]]; then
        action="${BASH_REMATCH[1]}"
        current="${BASH_REMATCH[2]}"
        # Skip if we've already seen this action
        [[ -n "${GHA_CURRENT[$action]:-}" ]] && continue
        GHA_CURRENT[$action]="$current"

        latest="unknown"
        if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
            # Convert action slug to API path
            api_url="https://api.github.com/repos/${action}/releases/latest"
            latest=$(curl -sfL "$api_url" 2>/dev/null | jq -r '.tag_name // "unknown"')
        fi
        GHA_LATEST[$action]="$latest"

        # For major version tags (v6), we only flag if the major version changed
        current_major="${current%%.*}"
        latest_major="${latest%%.*}"
        if [[ "$latest" == "unknown" ]]; then
            GHA_UPDATE[$action]="skip"
        elif [[ "$current_major" != "$latest_major" ]]; then
            GHA_UPDATE[$action]="yes"
        else
            GHA_UPDATE[$action]="no"
        fi
    fi
done < .github/workflows/ci.yaml

# ---------------------------------------------------------------------------
# 5. Upstream haproxy.cfg structural diff (informational — does not affect exit code)
# ---------------------------------------------------------------------------

info "Checking upstream haproxy.cfg for structural changes..."
if command -v curl >/dev/null 2>&1; then
    _upstream_cfg=$(curl -sfL "https://raw.githubusercontent.com/linuxserver/docker-socket-proxy/main/root/templates/haproxy.cfg" 2>/dev/null)
    if [[ -z "$_upstream_cfg" ]]; then
        err "Could not fetch upstream haproxy.cfg"
    else
        _local_cfg="socket-proxy/rootfs/templates/haproxy.cfg"
        # Compare http-request lines only (trimmed); exclude local-only @@ placeholder lines
        _upstream_rules=$(echo "$_upstream_cfg" | grep 'http-request' | sed 's/^[[:space:]]*//' | sort)
        _local_rules=$(grep 'http-request' "$_local_cfg" | grep -v '@@' | sed 's/^[[:space:]]*//' | sort)

        _new_upstream=$(comm -23 <(echo "$_upstream_rules") <(echo "$_local_rules"))
        _local_only=$(comm -13 <(echo "$_upstream_rules") <(echo "$_local_rules"))

        if [[ -z "$_new_upstream" && -z "$_local_only" ]]; then
            ok "haproxy.cfg http-request rules match upstream"
        else
            warn "haproxy.cfg differs from upstream — review before updating"
            if [[ -n "$_new_upstream" ]]; then
                echo "  Rules in upstream not in local (may need adopting):"
                echo "$_new_upstream" | sed 's/^/    /'
            fi
            if [[ -n "$_local_only" ]]; then
                echo "  Rules in local not in upstream (may be intentional):"
                echo "$_local_only" | sed 's/^/    /'
            fi
        fi
    fi
else
    err "curl not available; cannot check upstream haproxy.cfg"
fi

# ---------------------------------------------------------------------------
# Summary table
# ---------------------------------------------------------------------------

echo ""
echo "${BOLD}┌──────────────────────────────┬──────────────────┬──────────────────┬────────────────┐${NC}"
printf "${BOLD}│ %-28s │ %-16s │ %-16s │ %-14s │${NC}\n" "Dependency" "Current" "Latest" "Update?"
echo "${BOLD}├──────────────────────────────┼──────────────────┼──────────────────┼────────────────┤${NC}"

printf "│ %-28s │ %-16s │ %-16s │ %-14s │\n" "HA base image" "$BASE_IMAGE_TAG" "$BASE_IMAGE_LATEST" "$BASE_IMAGE_UPDATE"
printf "│ %-28s │ %-16s │ %-16s │ %-14s │\n" "HAProxy" "$HAPROXY_PIN" "$HAPROXY_LATEST" "$HAPROXY_UPDATE"
printf "│ %-28s │ %-16s │ %-16s │ %-14s │\n" "Upstream LS" "$UPSTREAM_RUN" "$UPSTREAM_LATEST" "$UPSTREAM_UPDATE"

for action in "${!GHA_CURRENT[@]}"; do
    printf "│ %-28s │ %-16s │ %-16s │ %-14s │\n" "$action" "${GHA_CURRENT[$action]}" "${GHA_LATEST[$action]}" "${GHA_UPDATE[$action]}"
done

echo "${BOLD}└──────────────────────────────┴──────────────────┴──────────────────┴────────────────┘${NC}"
echo ""

# ---------------------------------------------------------------------------
# Exit code
# ---------------------------------------------------------------------------

NEEDS_UPDATE=0
[[ "$BASE_IMAGE_UPDATE" == "yes" ]] && NEEDS_UPDATE=1
[[ "$HAPROXY_UPDATE" == "yes" ]] && NEEDS_UPDATE=1
[[ "$UPSTREAM_UPDATE" == "yes" ]] && NEEDS_UPDATE=1
for action in "${!GHA_UPDATE[@]}"; do
    [[ "${GHA_UPDATE[$action]}" == "yes" ]] && NEEDS_UPDATE=1
done

if [[ "$NEEDS_UPDATE" -eq 1 ]]; then
    warn "Updates are available. Run the fs-update workflow to apply them."
    exit 1
else
    ok "All dependencies are up to date."
    exit 0
fi
