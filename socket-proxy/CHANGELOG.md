# Changelog

## 1.4.3

- Correct the dual-stack note in the documentation. It claimed that with
  `DISABLE_IPV6` off, plain IPv4 `ALLOWED_CIDRS` entries would not match IPv4
  clients arriving as `::ffff:` addresses, and that the mapped form had to be
  added by hand. HAProxy matches them anyway (manual section 7.1.6), which was
  confirmed against HAProxy 3.4.4. No behaviour change; existing mapped
  entries keep working.
- Document that an IPv4 entry also matches 6to4 (`2002:IPV4::`) and
  IPv4-compatible (`::IPV4`) IPv6 clients on a dual-stack listener.
- Document IPv6 entries, the zone ID restriction and the fail-closed startup
  check added in 1.4.2.

## 1.4.2

- Tighten IPv6 validation of `ALLOWED_CIDRS` entries. The previous check
  accepted any run of hex digits, colons and dots containing a colon, so
  malformed entries such as `::::`, `fe80:::1` or `1.2.3.4.5:` were written
  into the HAProxy ACL file, where HAProxy treats them as a fatal
  configuration error and the add-on failed to start. Entries are now parsed
  properly: 1-4 hex digits per group, at most one `::`, the correct group
  count, an optional trailing IPv4 address, and a `/0-128` prefix. Invalid
  entries are skipped with a warning, as invalid IPv4 entries already were.
- Interface zone IDs (`fe80::1%eth0`) are rejected; HAProxy does not accept
  them in a `src` ACL.
- Fail closed when `ALLOWED_CIDRS` is set but none of its entries are valid.
  Previously an allowlist made entirely of invalid entries was dropped and the
  proxy started with no source-IP restriction at all. It now logs an error and
  refuses to start.

## 1.4.1

- Remove `protected: false` from `config.yaml`. The Supervisor only reads
  `protected` from installed-app state, not from the add-on manifest
  (`SCHEMA_APP_USER`, not `SCHEMA_APP_CONFIG`), so the key was silently
  discarded on every store load. Protection mode still has to be disabled by
  hand on the Info tab, exactly as before; the line only made it look
  otherwise.
- Remove the redundant `boot: auto`, which restates the Supervisor default.
- Add the Home Assistant app linter (`frenck/action-app-linter`) to the CI
  lint job.
- Validate every `schema:` expression in `config.yaml` against the
  Supervisor's own `RE_SCHEMA_ELEMENT` grammar in the test suite. Nothing
  previously checked that an expression such as
  `list(info|notice|warning|err|debug)` was parseable; a malformed one would
  only have surfaced as a broken config UI after install.

## 1.4.0

- Drop `full_access: true` from `config.yaml`. The Supervisor gates the Docker
  socket mount solely on `docker_api: true`; `full_access` only adds the device
  cgroup rule `a *:* rwm` (full read/write/mknod on every device node), which
  this add-on does not need. Reduces the add-on's own privilege with no change
  in function. Protection mode must still be disabled, as before.

## 1.3.1

- Bump HAProxy from 3.4.3-r0 to 3.4.4-r0 (Alpine 3.24 package update)
- Bump upstream reference to linuxserver/docker-socket-proxy 3.4.4-r0-ls96

## 1.3.0

- Add `ALLOW_ARCHIVE`, `ALLOW_CHANGES`, `ALLOW_EXPORT`, `ALLOW_LOGS` and `ALLOW_TOP`
  options (synced from upstream linuxserver/docker-socket-proxy 3.4.3-r0-ls93).
  These gate `/containers/{id}/...` sub-paths independently of `CONTAINERS` and
  `POST`. All default to on, so existing installs are unaffected.
- Bump HA base image from Alpine 3.23 to 3.24
- Bump HAProxy from 3.2.19-r0 to 3.4.3-r0
- Bump upstream reference to linuxserver/docker-socket-proxy 3.4.3-r0-ls93
- Update GitHub Actions: actions/setup-python v6 to v7

## 1.2.3

- Bump HAProxy from 3.2.18-r0 to 3.2.19-r0 (Alpine 3.23 package update)
- Bump upstream reference to linuxserver/docker-socket-proxy 3.2.19-r0-ls84

## 1.2.2

- Bump HAProxy from 3.2.16-r0 to 3.2.18-r0 (Alpine 3.23 package update)
- Bump upstream reference to linuxserver/docker-socket-proxy 3.2.18-r0-ls81

## 1.2.1

- Bump HAProxy from 3.2.15-r0 to 3.2.16-r0 (Alpine 3.23 package update)
- Bump upstream reference to linuxserver/docker-socket-proxy 3.2.16-r0-ls78

## 1.2.0

- Add `ALLOW_PAUSE` and `ALLOW_UNPAUSE` options — allow pausing and unpausing containers (synced from upstream linuxserver/docker-socket-proxy 3.2.15-r0-ls75)
- Bump upstream reference to linuxserver/docker-socket-proxy 3.2.15-r0-ls75
- Update pre-commit hooks: pre-commit-hooks v6.0.0, yamllint v1.38.0, shellcheck-py v0.11.0.1, hadolint v2.14.0
- Update GitHub Actions: actions/checkout v6, actions/setup-python v6

## 1.1.2

- Bump HAProxy from 3.2.13-r0 to 3.2.15-r0 (Alpine 3.23 package update)

## 1.1.1

- Add optional `ALLOWED_CIDRS` source-IP allowlist — restrict which IPs/CIDRs may connect to the proxy listener
- **Breaking change:** `DISABLE_IPV6` now defaults to `true` (IPv4-only). Previously the proxy bound dual-stack by default. If you rely on IPv6 connectivity, explicitly set `DISABLE_IPV6: false` after upgrading.

## 1.1.0

- Bump HA base image from Alpine 3.21 to 3.23
- Bump HAProxy from 3.0.17-r0 to 3.2.13-r0

## 1.0.3

- Add store-facing README with protection mode requirement and Dozzle quick start
- Update all documentation with Dozzle setup, required endpoints, and troubleshooting
- Add protection mode note to config.yaml description

## 1.0.2

- Add `docker_api: true` to mount Docker socket into container
- Auto-detect socket path with clear error if not found
- Add startup banner with version, upstream pin, and config summary

## 1.0.1

- Pin haproxy package version in Dockerfile (`3.0.17-r0`)
- Fix shellcheck warnings in run script (separate declare and export)
- Remove misleading shellcheck directive from execlineb finish script
- Add pre-commit hooks, test suite, Makefile, and GitHub Actions CI

## 1.0.0

- Initial release
- HAProxy-based Docker socket proxy with per-endpoint access control
- Based on LinuxServer docker-socket-proxy 3.2.13-r0-ls70
