# Docker Socket Proxy

Filtered, read-only Docker socket proxy for Home Assistant OS. Provides controlled access to the Docker API over TCP using HAProxy, so tools like [Dozzle][dozzle] can monitor your HAOS containers remotely without exposing the full Docker socket.

Based on [LinuxServer docker-socket-proxy][upstream].

## Prerequisites

This add-on requires **Protection mode** to be **disabled** for Docker socket access:

1. Go to the add-on's **Info** tab
2. Toggle off **Protection mode**
3. Start the add-on

## Quick Start for Dozzle

Enable these options in the add-on configuration:

| Option | Required |
|--------|----------|
| CONTAINERS | on |
| INFO | on |
| EVENTS | on (default) |
| PING | on (default) |
| VERSION | on (default) |

Then on your remote Dozzle host:

```yaml
# docker-compose.yml
services:
  dozzle:
    image: amir20/dozzle:latest
    ports:
      - "8080:8080"
    environment:
      DOZZLE_REMOTE_HOST: "tcp://<haos-ip>:2375|homeassistant"
```

## How It Works

All Docker API requests pass through HAProxy, which enforces per-endpoint access control. By default only GET requests are allowed, and each API endpoint must be explicitly enabled. This means you expose only what you need — nothing more.

On startup the add-on logs a summary of enabled endpoints so you can verify the configuration at a glance.

See the [full documentation][docs] for all configuration options and troubleshooting.

[dozzle]: https://dozzle.dev/
[upstream]: https://github.com/linuxserver/docker-socket-proxy
[docs]: https://github.com/fergus/haos-docker-socket-proxy/blob/main/socket-proxy/DOCS.md
