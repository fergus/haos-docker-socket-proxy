# Changelog

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
