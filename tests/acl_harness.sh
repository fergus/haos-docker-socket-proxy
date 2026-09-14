#!/usr/bin/env bash
#
# Docker Socket Proxy - Home Assistant add-on
# Copyright (C) 2025 Fergus Stevens
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# ACL behaviour harness. Runs inside the add-on image (see the "ACL behaviour"
# section of tests/test_addon.sh) so the shipped HAProxy build and template are
# what gets tested. A second HAProxy frontend bound to the backend Unix socket
# stands in for the Docker daemon and answers 200, so every request has one of
# three outcomes:
#   200  passed the ACL and reached the backend
#   403  denied by an http-request rule
#   000  connection rejected by the source-IP allowlist
#
# Prints "PASS: ..." / "FAIL: ..." lines and a final "DONE". Exits non-zero only
# if the harness itself cannot run.
set -uo pipefail

# Every bool option in config.yaml except DISABLE_IPV6. test_addon.sh asserts
# this list is complete, so a new toggle cannot leak between cases.
TOGGLES="ALLOW_ARCHIVE ALLOW_CHANGES ALLOW_EXPORT ALLOW_LOGS ALLOW_TOP ALLOW_RESTARTS ALLOW_START ALLOW_STOP ALLOW_PAUSE ALLOW_UNPAUSE POST AUTH BUILD COMMIT CONFIGS CONTAINERS DISTRIBUTION EVENTS EXEC GRPC IMAGES INFO NETWORKS NODES PING PLUGINS SECRETS SERVICES SESSION SWARM SYSTEM TASKS VERSION VOLUMES"

WORK=$(mktemp -d)
SOCK="${WORK}/docker.sock"
PORT=2375

die() { echo "harness error: $1" >&2; exit 2; }

command -v haproxy >/dev/null || die "haproxy not found"
command -v curl >/dev/null || die "curl not found"
[[ -f /templates/haproxy.cfg ]] || die "/templates/haproxy.cfg not found"

cat > "${WORK}/stub.cfg" <<CFG
frontend docker_stub
    mode http
    bind unix@${SOCK}
    http-request return status 200
CFG

# $1: space-separated NAME=1 toggles to enable; $2: optional allowlist entry
start_proxy() {
    local t kv acl="" rej=""
    for t in ${TOGGLES}; do export "${t}=0"; done
    for kv in $1; do export "${kv?}"; done
    export LOG_LEVEL=err SOCKET_PATH="${SOCK}"
    if [[ -n "${2:-}" ]]; then
        printf '%s\n' "$2" > "${WORK}/allowed_ips.acl"
        acl="acl allowed_src src -f ${WORK}/allowed_ips.acl"
        rej="tcp-request connection reject if !allowed_src"
    fi
    sed -e "s|@@BIND_PROTO@@|:${PORT}|g" \
        -e "s|@@ALLOWED_SRC_ACL@@|${acl}|g" \
        -e "s|@@ALLOWED_SRC_REJECT@@|${rej}|g" \
        /templates/haproxy.cfg > "${WORK}/proxy.cfg"
    rm -f "${SOCK}"
    haproxy -q -D -p "${WORK}/pid" -f "${WORK}/proxy.cfg" -f "${WORK}/stub.cfg" \
        || die "haproxy failed to start with: $1"
    for _ in $(seq 1 100); do
        [[ -S "${SOCK}" ]] && return 0
        sleep 0.05
    done
    die "backend stub socket never appeared"
}

stop_proxy() {
    local pid
    pid=$(cat "${WORK}/pid")
    kill "${pid}"
    while kill -0 "${pid}" 2>/dev/null; do sleep 0.05; done
}

# $1 expected (200|403|000), $2 method, $3 path, $4 description
check() {
    local got
    if [[ "$2" == HEAD ]]; then
        got=$(curl -s --path-as-is --head -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}$3")
    else
        got=$(curl -s --path-as-is -X "$2" -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}$3")
    fi
    if [[ "${got}" == "$1" ]]; then
        echo "PASS: acl: $4 ($2 $3 -> $got)"
    else
        echo "FAIL: acl: $4 ($2 $3 -> $got, expected $1)"
    fi
}

start_proxy ""
check 403 GET /_ping              "all off denies /_ping"
check 403 GET /version            "all off denies /version"
check 403 GET /containers/json    "all off denies /containers/json"
check 403 GET /no/such/endpoint   "unmatched path hits the final deny"
stop_proxy

start_proxy "PING=1 VERSION=1"
check 200 GET  /_ping             "PING on allows /_ping"
check 200 GET  /version           "VERSION on allows /version"
check 200 GET  /v1.43/_ping       "versioned path is matched"
check 200 HEAD /_ping             "HEAD counts as GET (METH_GET)"
check 403 GET  /containers/json   "PING/VERSION on does not open /containers"
check 403 POST /_ping             "POST off denies non-GET methods"
stop_proxy

start_proxy "CONTAINERS=1"
check 200 GET  /containers/json             "CONTAINERS on allows /containers/json"
check 200 GET  /v1.43/containers/json       "CONTAINERS on allows versioned /containers/json"
check 403 GET  /containers/abc/logs         "ALLOW_LOGS off denies logs (early deny)"
check 403 GET  /v1.43/containers/abc/logs   "ALLOW_LOGS off denies versioned logs"
check 403 GET  /containers/abc/top          "ALLOW_TOP off denies top"
check 403 GET  /containers/abc/archive      "ALLOW_ARCHIVE off denies archive"
check 403 GET  /containers/abc/changes      "ALLOW_CHANGES off denies changes"
check 403 GET  /containers/abc/export       "ALLOW_EXPORT off denies export"
check 403 POST /containers/create           "POST off denies container create"
# INT-96: non-canonical paths currently slip past the early deny. dockerd
# 301-redirects them to the clean path today; flip these when INT-96 lands.
check 200 GET  /containers//abc/logs        "INT-96 characterisation: double slash skips logs deny"
check 200 GET  /containers/abc/../abc/logs  "INT-96 characterisation: dot-segment skips logs deny"
stop_proxy

start_proxy "PING=1"
check 200 GET /_ping/../containers/json     "INT-96 characterisation: dot-segment escapes the /_ping allow"
stop_proxy

start_proxy "CONTAINERS=1 ALLOW_LOGS=1"
check 200 GET /containers/abc/logs          "ALLOW_LOGS on allows logs"
stop_proxy

start_proxy "ALLOW_START=1"
check 200 POST   /containers/abc/start      "ALLOW_START allows start without POST"
check 403 POST   /containers/abc/stop       "ALLOW_START does not allow stop"
# INT-97: write allows do not check the method.
check 200 DELETE /containers/abc/start      "INT-97 characterisation: write allow ignores method"
stop_proxy

start_proxy "ALLOW_STOP=1"
check 200 POST /containers/abc/stop         "ALLOW_STOP allows stop"
check 403 POST /containers/abc/kill         "ALLOW_STOP without ALLOW_RESTARTS denies kill"
check 403 POST /containers/abc/restart      "ALLOW_STOP without ALLOW_RESTARTS denies restart"
stop_proxy

start_proxy "ALLOW_RESTARTS=1"
check 200 POST /containers/abc/stop         "ALLOW_RESTARTS allows stop"
check 200 POST /containers/abc/kill         "ALLOW_RESTARTS allows kill"
check 200 POST /containers/abc/restart      "ALLOW_RESTARTS allows restart"
stop_proxy

start_proxy "ALLOW_PAUSE=1 ALLOW_UNPAUSE=1"
check 200 POST /containers/abc/pause        "ALLOW_PAUSE allows pause"
check 200 POST /containers/abc/unpause      "ALLOW_UNPAUSE allows unpause"
stop_proxy

start_proxy "CONTAINERS=1 POST=1"
check 403 GET  /containers/abc/logs         "POST on does not bypass the early logs deny"
# INT-97: POST is a master switch over the granular write toggles.
check 200 POST   /containers/abc/kill       "INT-97 characterisation: POST allows kill with ALLOW_RESTARTS off"
check 200 DELETE /containers/abc            "INT-97 characterisation: POST allows container delete"
stop_proxy

start_proxy "PING=1" "10.0.0.0/8"
check 000 GET /_ping                        "allowlist rejects a source outside it"
stop_proxy

start_proxy "PING=1" "127.0.0.0/8"
check 200 GET /_ping                        "allowlist admits a source inside it"
stop_proxy

echo "DONE"
