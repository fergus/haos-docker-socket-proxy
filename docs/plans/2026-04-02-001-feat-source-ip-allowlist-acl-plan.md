---
title: "feat: Add optional source-IP allowlist ACL to socket proxy listener"
type: feat
status: completed
date: 2026-04-02
---

# feat: Add optional source-IP allowlist ACL to socket proxy listener

## Overview

Add a new optional `ALLOWED_CIDRS` configuration option that restricts which source IP addresses or CIDR ranges may connect to the Docker socket proxy on TCP port 2375. When the list is non-empty, connections from unlisted sources are rejected at the TCP layer before any HTTP processing. When the list is empty (the default), all sources are permitted — preserving existing behaviour.

This is the first caller-restriction layer in the add-on and directly addresses the critical finding from the adversarial code review: the proxy currently exposes an unauthenticated TCP listener on all interfaces with no network-level access control.

## Problem Statement / Motivation

The Docker socket proxy binds to `ipv6@:2375` (dual-stack) or `0.0.0.0:2375` (IPv4-only) and publishes that port on the host network. Any host that can reach the HAOS machine can query or — with write toggles enabled — control Docker. The add-on currently has no mechanism to restrict connections by source IP. A user who wants to allow only their Dozzle container or Portainer host has no option to enforce that.

The `ALLOWED_CIDRS` feature closes this gap with a standard HAProxy `src` ACL enforced at TCP connection time, requiring zero changes to the HTTP-layer ACL logic.

## Proposed Solution

### Configuration surface

Add a new array-of-strings option `ALLOWED_CIDRS` in `config.yaml`:

```yaml
# config.yaml — options block (alphabetical order)
options:
  ALLOWED_CIDRS: []

# config.yaml — schema block (alphabetical order)
schema:
  ALLOWED_CIDRS:
    - str
```

Empty array = no restriction (existing behaviour). Non-empty array = only listed IPs/CIDRs may connect.

### HAProxy template approach

Rather than using `opt@` with a permanent `acl` line, both the ACL definition line and the `tcp-request` reject rule are injected together via a single `@@ALLOWED_SRC@@` placeholder. This keeps the template clean when the feature is disabled and avoids the edge case where an empty ACL file causes `opt@` to silently pass `allowed_src` as always-false while a reject rule is present.

**`haproxy.cfg` frontend block (partial):**
```
frontend proxy
    bind @@BIND_PROTO@@
    mode http
    @@ALLOWED_SRC@@
    http-request deny unless METH_GET || { env(POST) -m bool }
    ...
```

When `ALLOWED_CIDRS` is non-empty, `@@ALLOWED_SRC@@` expands to two lines:
```
    acl allowed_src src -f /run/haproxy/allowed_ips.acl
    tcp-request connection reject if !allowed_src
```

When `ALLOWED_CIDRS` is empty, `@@ALLOWED_SRC@@` expands to an empty string (no ACL, no reject rule, no change in behaviour).

### Run script changes (`run`)

```bash
# After existing option reads, before sed substitution

# Source-IP allowlist
ALLOWED_SRC=""
if ! bashio::config.is_empty 'ALLOWED_CIDRS'; then
    mkdir -p /run/haproxy
    : > /run/haproxy/allowed_ips.acl        # truncate/create
    while IFS= read -r cidr; do
        # strip whitespace
        cidr=$(echo "$cidr" | tr -d '[:space:]')
        [ -z "$cidr" ] && continue
        echo "$cidr" >> /run/haproxy/allowed_ips.acl
    done < <(bashio::config 'ALLOWED_CIDRS[]')
    ALLOWED_SRC=$'    acl allowed_src src -f /run/haproxy/allowed_ips.acl\n    tcp-request connection reject if !allowed_src'
    bashio::log.info "Source-IP allowlist active: $(paste -sd, /run/haproxy/allowed_ips.acl)"
else
    bashio::log.info "Source-IP allowlist: disabled (all sources permitted)"
fi
export ALLOWED_SRC
```

Extend the existing `sed` substitution to handle both placeholders using `-e` expressions and `|` delimiters throughout (CIDR strings contain `/` which would break `/`-delimited sed):

```bash
sed \
    -e "s|@@BIND_PROTO@@|${BIND_PROTO}|g" \
    -e "s|@@ALLOWED_SRC@@|${ALLOWED_SRC}|g" \
    /templates/haproxy.cfg > /run/haproxy/haproxy.cfg
```

### IPv4-mapped IPv6 address interaction (critical)

When `DISABLE_IPV6` is false (the default), HAProxy binds `ipv6@:2375` and IPv4 connections arrive with source address `::ffff:x.x.x.x`. HAProxy's `src` ACL matching does **not** automatically normalise these to bare IPv4. A user who adds only `192.168.1.0/24` to their allowlist will have all IPv4 clients rejected when dual-stack is active.

**Mitigation options (implementer to choose one):**

1. **Document the limitation** — warn users in DOCS.md that when `DISABLE_IPV6` is false, IPv4 callers must be listed as IPv4-mapped IPv6 CIDRs (`::ffff:192.168.1.0/112`) in addition to bare IPv4 form. Simplest, no code change.
2. **Auto-generate both forms** — in the run script, for each IPv4 CIDR in the list, also emit its `::ffff:x.x.x.x/prefix+96` equivalent. More complex, better UX.
3. **Require IPv4-only bind when allowlist is active** — emit `bashio::log.warning` and force `DISABLE_IPV6=true` when both `ALLOWED_CIDRS` is non-empty and `DISABLE_IPV6` is false.

Option 1 is recommended for v1 given its simplicity. Options 2 or 3 can be implemented in a follow-up.

## Technical Considerations

- **TCP-layer vs HTTP-layer**: `tcp-request connection reject` fires before HAProxy initialises HTTP parsing. This is more efficient than `http-request deny` and correct for pure IP gating where no HTTP attributes are needed. It produces a TCP RST rather than an HTTP 4xx response.
- **`sed` delimiter**: All `sed` substitution expressions must use `|` as the delimiter (not `/`) because CIDR values contain `/` characters.
- **Multiline `sed` substitution**: The `$'...\n...'` ANSI-C quoting form produces a literal newline inside the shell variable so that `sed` injects both HAProxy lines correctly.
- **ACL file lifetime**: `/run/haproxy/` is tmpfs in the container and recreated on every add-on start, so there is no stale-file risk across restarts.
- **HAOS schema type**: The `[str]` / `- str` array-of-strings schema type is confirmed supported by HAOS add-on configuration. Verify against HA developer docs before implementation if in doubt.
- **Bashio array iteration**: Use `bashio::config 'ALLOWED_CIDRS[]'` (with `[]` suffix) to iterate each array element.

## System-Wide Impact

- **Interaction graph**: `config.yaml` option read by bashio → ACL file written to tmpfs → `sed` injects two HAProxy directive lines → HAProxy enforces `tcp-request connection reject` before HTTP-layer processing → all existing HTTP-layer ACLs fire only for connections that passed the IP gate.
- **Error propagation**: An invalid CIDR string written verbatim to the ACL file will cause HAProxy to log an error at startup and either skip the line or fail to start (version-dependent). There is no run-script validation of CIDR format; this is deferred to a follow-up.
- **State lifecycle**: Stateless per restart. ACL file is written fresh on every add-on start from the current config. No persistent state concern.
- **API surface parity**: No other interface exposes equivalent functionality; this is the only network entry point.
- **Integration test scenarios**: The run script's conditional template-rendering logic is untested by the existing static-analysis suite. Runtime rendering tests are needed (see Acceptance Criteria).

## Acceptance Criteria

### Functional

- [ ] `ALLOWED_CIDRS: []` (empty, default) renders a `haproxy.cfg` with no `acl allowed_src` line and no `tcp-request` rule — HAProxy behaviour is identical to v1.1.0
- [ ] `ALLOWED_CIDRS: ["192.168.1.5"]` writes `/run/haproxy/allowed_ips.acl` containing `192.168.1.5` and renders `haproxy.cfg` with both the `acl allowed_src src -f ...` line and `tcp-request connection reject if !allowed_src`
- [ ] Multiple CIDR entries are each written on a separate line in the ACL file
- [ ] The `@@BIND_PROTO@@` substitution is unaffected by the addition of the second `sed` expression
- [ ] Upgrading from v1.1.0 (no `ALLOWED_CIDRS` key in stored config) produces the same behaviour as an explicitly empty array

### Documentation

- [ ] `ALLOWED_CIDRS` is documented in a new "Access Control" or "Connection Filtering" section in `DOCS.md` with default, description, and an example value
- [ ] DOCS.md troubleshooting section includes a new entry for "Connection reset or refused from a running add-on" that points to a misconfigured allowlist as the cause
- [ ] `translations/en.yaml` has a matching `ALLOWED_CIDRS` entry with name and description
- [ ] IPv4-mapped IPv6 limitation is documented (when `DISABLE_IPV6` is false, IPv4 clients must be listed in IPv4-mapped form or `DISABLE_IPV6` must be enabled)

### Observability

- [ ] Startup log emits the active CIDR list when `ALLOWED_CIDRS` is non-empty
- [ ] Startup log emits "Source-IP allowlist: disabled (all sources permitted)" when the list is empty

### Tests

- [ ] `tests/test_addon.sh` consistency checks pass (translation, schema, run-script coverage)
- [ ] New test section in `tests/test_addon.sh` verifies: with a mock non-empty `ALLOWED_CIDRS`, the rendered `haproxy.cfg` contains `tcp-request connection reject if !allowed_src`; with an empty list, the rendered config does not contain that line

## Dependencies & Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| IPv4-mapped IPv6 silently rejects valid clients in dual-stack mode | High if users add IPv4 CIDRs without knowing | Document prominently; recommend `DISABLE_IPV6: true` when using allowlist |
| Invalid CIDR string causes HAProxy startup failure | Low (most users enter valid IPs) | Deferred to follow-up; document that entries must be valid IP/CIDR notation |
| Multiline `sed` substitution breaks on some Alpine `sed` implementations | Low (POSIX `sed` handles `$'...'` in bash) | Test on Alpine in CI; fallback to writing a temp partial config |
| HAOS `schema: [str]` type not behaving as expected in bashio | Low (confirmed in HA addon docs) | Verify with a test build before shipping |

## Sources & References

### Internal

- HAProxy template: `socket-proxy/rootfs/templates/haproxy.cfg`
- Run script: `socket-proxy/rootfs/etc/services.d/socket-proxy/run`
- Addon config: `socket-proxy/config.yaml`
- Translations: `socket-proxy/translations/en.yaml`
- Documentation: `socket-proxy/DOCS.md`
- Test suite: `tests/test_addon.sh`

### External

- [HAProxy ACL Documentation](https://www.haproxy.com/documentation/haproxy-configuration-tutorials/proxying-essentials/custom-rules/acls/)
- [HAProxy Traffic Policing with `tcp-request`](https://www.haproxy.com/documentation/haproxy-configuration-tutorials/security/traffic-policing/)
- [Home Assistant Add-on Configuration Schema](https://developers.home-assistant.io/docs/add-ons/configuration/)
- Samba add-on `config.yaml` — real-world `- str` array schema example
