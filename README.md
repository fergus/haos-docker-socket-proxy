# Home Assistant Add-on: Docker Socket Proxy

Filtered, read-only Docker socket proxy for Home Assistant OS. Allows tools like Dozzle to monitor HAOS containers remotely without exposing the full Docker socket.

## Installation

1. In Home Assistant, go to **Settings → Add-ons → Add-on Store**
2. Click the three-dot menu (top right) → **Repositories**
3. Add this repository URL:
   ```
   https://github.com/fergus/haos-docker-socket-proxy
   ```
4. Find "Docker Socket Proxy" in the store and click **Install**
5. **Disable Protection mode** — go to the add-on's Info tab and toggle off "Protection mode" (required for Docker socket access)
6. Configure the options and start the add-on

## Configuration

See the [add-on documentation](socket-proxy/DOCS.md) for full configuration details.

## Quick Start for Dozzle

1. Disable **Protection mode** on the add-on (Info tab)
2. Enable these options in the add-on configuration:
   - `CONTAINERS` — on
   - `INFO` — on
   - `EVENTS` — on (default)
   - `PING` — on (default)
   - `VERSION` — on (default)
3. Start the add-on
4. On your remote Dozzle host, point it at `tcp://<haos-ip>:2375`

## Development

Prerequisites: Python 3, Docker, and optionally [pre-commit](https://pre-commit.com/).

```bash
make setup    # install pre-commit hooks
make lint     # run all linters (yamllint, shellcheck, hadolint, etc.)
make test     # run the test suite
make build    # docker build the add-on image
make all      # lint + test + build
```

The test suite (`tests/test_addon.sh`) validates file structure, YAML syntax, config consistency (options ↔ schema ↔ translations ↔ run script), and the Docker build. It gracefully skips checks when tools are missing.
