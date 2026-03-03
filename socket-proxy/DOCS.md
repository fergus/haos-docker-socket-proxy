# Docker Socket Proxy

This add-on runs an HAProxy-based Docker socket proxy, providing filtered, read-only access to the Docker API over TCP. It replicates the approach used by the [LinuxServer docker-socket-proxy](https://github.com/linuxserver/docker-socket-proxy) image, adapted for Home Assistant OS add-on conventions.

## Use Case

The primary use case is allowing tools like [Dozzle](https://dozzle.dev/) running on a remote host to monitor HAOS containers without exposing the full Docker socket.

## Configuration

### Port

- **port** (default: `2375`): TCP port the proxy listens on.

### API Endpoint Toggles

Each toggle is `0` (disabled) or `1` (enabled). By default, only read-only endpoints needed for monitoring are enabled.

| Option | Default | Description |
|--------|---------|-------------|
| CONTAINERS | 0 | Container list, inspect, logs |
| EVENTS | 1 | Docker event stream |
| IMAGES | 0 | Image list and inspect |
| INFO | 0 | Docker system info |
| NETWORKS | 0 | Network list and inspect |
| PING | 1 | Health check endpoint |
| VERSION | 1 | Docker version info |
| VOLUMES | 0 | Volume list and inspect |

### Write Operation Toggles

| Option | Default | Description |
|--------|---------|-------------|
| POST | 0 | Allow all POST requests (default: GET only) |
| ALLOW_START | 0 | Allow starting containers |
| ALLOW_STOP | 0 | Allow stopping containers |
| ALLOW_RESTARTS | 0 | Allow restart/stop/kill operations |

### Other Toggles

AUTH, BUILD, COMMIT, CONFIGS, DISTRIBUTION, EXEC, GRPC, NODES, PLUGINS, SECRETS, SERVICES, SESSION, SWARM, SYSTEM, TASKS — all default to `0`.

### Other Options

- **DISABLE_IPV6** (default: `0`): Set to `1` to bind IPv4 only.
- **LOG_LEVEL** (default: `info`): HAProxy log level (`debug`, `info`, `notice`, `warning`, `err`).

## Connecting Dozzle

On your remote Dozzle host, add the HAOS instance as a remote agent:

```yaml
# dozzle docker-compose.yml
services:
  dozzle:
    image: amir20/dozzle:latest
    ports:
      - "8080:8080"
    environment:
      DOZZLE_REMOTE_HOST: "tcp://<haos-ip>:2375|homeassistant"
```

For Dozzle, you need at minimum: `CONTAINERS: 1`, `EVENTS: 1`, `VERSION: 1`, `PING: 1`.

## Updating from Upstream

This add-on tracks [linuxserver/docker-socket-proxy](https://github.com/linuxserver/docker-socket-proxy). To check for upstream changes:

```bash
curl -sL https://raw.githubusercontent.com/linuxserver/docker-socket-proxy/main/root/templates/haproxy.cfg \
  | diff - socket-proxy/rootfs/templates/haproxy.cfg
```

When updating:
1. Compare upstream `haproxy.cfg` template and update `rootfs/templates/haproxy.cfg`
2. Check upstream Dockerfile `ENV` block for new environment variables
3. Add any new variables to `config.yaml` options/schema and `translations/en.yaml`
4. Update the version pin comment in `build.yaml`
5. Bump version in `config.yaml` and update `CHANGELOG.md`
