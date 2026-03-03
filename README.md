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
5. Configure the options (enable `CONTAINERS` for Dozzle) and start the add-on

## Configuration

See the [add-on documentation](socket-proxy/DOCS.md) for full configuration details.

## Quick Start for Dozzle

Enable these options in the add-on configuration:
- `CONTAINERS: 1`
- `EVENTS: 1` (default)
- `PING: 1` (default)
- `VERSION: 1` (default)

Then point Dozzle at `tcp://<haos-ip>:2375`.
