# Docker Socket Proxy

This add-on runs an HAProxy-based Docker socket proxy, access to the Docker API over TCP. It replicates the approach used by the [LinuxServer docker-socket-proxy](https://github.com/linuxserver/docker-socket-proxy) image, adapted for Home Assistant OS App conventions.

## Use Case

The primary use case is allowing tools like [Dozzle](https://dozzle.dev/) running on a remote host to monitor HAOS containers without exposing the full Docker socket.

## Important: Protection Mode

This add-on requires **Protection mode** to be **disabled** before starting. The add-on uses `docker_api` to access the Docker socket, which is only available to unprotected add-ons.

To disable Protection mode:
1. Go to **Settings → Add-ons → Docker Socket Proxy**
2. On the **Info** tab, toggle off **Protection mode**
3. Start or restart the add-on

If Protection mode is **enabled**, the add-on will fail to start with a "Docker socket not found" error.

## Configuration

### Port

- **port** (default: `2375`): TCP port the proxy listens on.

### API Endpoint Toggles

Each toggle is on (enabled) or off (disabled). By default, only read-only endpoints needed for basic monitoring are enabled.

| Option | Default | Description |
|--------|---------|-------------|
| CONTAINERS | off | Container list, inspect, logs |
| EVENTS | on | Docker event stream |
| IMAGES | off | Image list and inspect |
| INFO | off | Docker system info |
| NETWORKS | off | Network list and inspect |
| PING | on | Health check endpoint |
| VERSION | on | Docker version info |
| VOLUMES | off | Volume list and inspect |

### Write Operation Toggles

These options allow write (POST) access to the Docker API. Enable with caution.

| Option | Default | Description |
|--------|---------|-------------|
| POST | off | Allow all POST requests (default: GET only) |
| ALLOW_START | off | Allow starting containers |
| ALLOW_STOP | off | Allow stopping containers |
| ALLOW_RESTARTS | off | Allow restart/stop/kill operations |

Write operations are logged as warnings on startup to highlight when they are enabled.

### Other Toggles

AUTH, BUILD, COMMIT, CONFIGS, DISTRIBUTION, EXEC, GRPC, NODES, PLUGINS, SECRETS, SERVICES, SESSION, SWARM, SYSTEM, TASKS — all default to off.

### Access Control

- **ALLOWED_CIDRS** (default: empty — all sources permitted): Optional list of IP addresses or CIDR ranges that may connect to the proxy. When non-empty, connections from any unlisted source are rejected at the TCP layer before any API processing.

  Example values: `192.168.1.5`, `192.168.1.0/24`, `10.0.0.0/8`

  > **IPv6 note:** If you enable `DISABLE_IPV6: off` (dual-stack), IPv4 client addresses arrive at HAProxy as IPv4-mapped IPv6 addresses (e.g. `::ffff:192.168.1.5`). Plain IPv4 CIDR entries will **not** match in this mode — you must also add the mapped form (e.g. `::ffff:192.168.1.0/112`). It is strongly recommended to keep `DISABLE_IPV6` enabled (the default) when using `ALLOWED_CIDRS`.

### Other Options

- **DISABLE_IPV6** (default: on): Bind IPv4 only. Disable to use dual-stack (see IPv6 note in Access Control above).
- **LOG_LEVEL** (default: `info`): HAProxy log level (`debug`, `info`, `notice`, `warning`, `err`).

## Connecting Dozzle

Dozzle requires the following endpoints to be enabled:

| Option | Required for |
|--------|-------------|
| CONTAINERS | Container list, inspect, and logs |
| INFO | Docker system info (host details, CPU, memory) |
| EVENTS | Real-time container event stream |
| PING | Health check / connectivity test |
| VERSION | Docker version info |

### Setup

1. Install and configure this add-on with the options above enabled
2. Disable **Protection mode** and start the add-on
3. On your remote Dozzle host, add the HAOS instance as a remote agent:

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

### Troubleshooting Dozzle

- **503 Service Unavailable** — The Docker socket is not mounted. Ensure Protection mode is disabled and restart the add-on.
- **403 Forbidden** / "Failed to get docker info" — A required endpoint is not enabled. Check the add-on logs for the "Enabled:" line and ensure `CONTAINERS`, `INFO`, `EVENTS`, `PING`, and `VERSION` are all listed.
- **Connection refused** — The add-on is not running, or the port/IP is incorrect. Verify the add-on is started and check the configured port.
- **Connection reset immediately (with add-on running)** — The source IP is not in `ALLOWED_CIDRS`. Check the add-on log for the `Allowlist:` line to confirm which CIDRs are active. If using dual-stack (default), see the IPv4/dual-stack note in the Access Control section.
