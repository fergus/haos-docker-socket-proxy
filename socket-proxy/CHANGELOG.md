# Changelog

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
