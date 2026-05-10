# G2Ray

> A GitHub Codespaces XHTTP edge relay for your own upstream Xray server.

## ⚠️ Important Notice

**Please read this before using this project:**

This project no longer runs a full V2Ray/Xray/VLESS proxy server inside GitHub Codespaces. It starts a lightweight HTTP reverse proxy that relays XHTTP traffic to an Xray server you already control. You are responsible for complying with GitHub's Terms of Service, the terms of your upstream hosting provider, and all applicable laws.

## What Changed

G2Ray used to terminate VLESS inside the Codespace and send traffic directly to the internet. This refactor changes the Codespace into a thin relay:

```text
VLESS + XHTTP client
        │
        ▼
GitHub Codespaces forwarded HTTPS URL
        │  (nginx HTTP relay; no local V2Ray/Xray core)
        ▼
Your upstream Xray server over HTTP or HTTPS
        │
        ▼
Internet / private destination handled by your server
```

That means:

- The Codespace does **not** validate VLESS users.
- The Codespace does **not** run a local Xray core.
- The Codespace does **not** provide the final outbound internet connection.
- Your upstream Xray server remains responsible for UUIDs, Reality/TLS, routing, logging, access control, and outbound policy.

## Required Configuration

Set the upstream URL before starting the container. The easiest option is `.devcontainer/config.json`:

```json
{
  "upstreamUrl": "https://your-xray-server.example.com/xhttp"
}
```

You can still override it with a Codespaces secret or environment variable when you do not want the URL in the repository:

```bash
G2RAY_UPSTREAM_URL=https://your-xray-server.example.com/xhttp
```

Supported upstream URL schemes:

- `https://...` for a TLS-protected upstream XHTTP endpoint
- `http://...` for a plain HTTP upstream XHTTP endpoint when you already protect that hop another way

Optional environment variables:

```bash
G2RAY_LISTEN_PORT=443
G2RAY_CONFIG_FILE=/path/to/config.json
G2RAY_LOG_LEVEL=info
G2RAY_ACCESS_LOG=on
```

`.devcontainer/config.json` also supports `listenPort`, `logLevel`, and `accessLog`. Environment variables take precedence over values in the JSON config file.

`G2RAY_LOG_LEVEL` controls nginx error logging and startup verbosity. Supported values are `debug`, `info`, `notice`, `warn`, `error`, `crit`, `alert`, and `emerg`. `G2RAY_ACCESS_LOG` accepts `on` or `off`; when enabled, access logs are emitted as structured JSON to stdout.

If no upstream URL is configured, the container stays alive and prints setup instructions instead of pretending to run a proxy.

## Upstream Xray Requirements

Your upstream server should expose an XHTTP-compatible inbound. The exact Xray configuration depends on your deployment, but it should match the upstream URL you configure in `.devcontainer/config.json` or `G2RAY_UPSTREAM_URL`:

- The hostname in the upstream URL must route to your server.
- The path in the upstream URL must match the XHTTP path expected by the upstream server.
- Your client credentials must match the upstream Xray server, not this Codespace.
- For HTTPS upstreams, the relay sends SNI using the upstream hostname.

## Setup in GitHub Codespaces

1. Fork this repository.
2. Put your upstream Xray XHTTP URL in `.devcontainer/config.json` as `upstreamUrl`, or add a repository/account Codespaces secret named `G2RAY_UPSTREAM_URL`.
3. Open the repository in GitHub Codespaces.
4. Wait for the dev container to build and start.
5. Use the forwarded Codespaces URL as the client-facing host.

GitHub exposes forwarded ports with a URL like:

```text
https://<codespace-name>-443.app.github.dev
```

Configure your VLESS + XHTTP client with:

- **Address / host:** the forwarded Codespaces hostname
- **Port:** `443`
- **Security:** TLS for the Codespaces URL
- **Transport:** XHTTP
- **Path:** the same XHTTP path your upstream expects, or the path embedded in the configured upstream URL
- **UUID and other credentials:** the credentials configured on your upstream Xray server

## Local Files

The refactor is intentionally small at runtime:

- `.devcontainer/Dockerfile` installs nginx and helper tools only.
- `.devcontainer/startup.sh` loads the optional JSON config file, validates the upstream URL, renders nginx configuration, and starts the relay with structured startup logs.
- `.devcontainer/nginx.conf.template` disables proxy buffering and request buffering for long-lived XHTTP streams, emits JSON access logs, and forwards request IDs upstream.
- `.devcontainer/config.json` is the optional local place to set `upstreamUrl`, `listenPort`, `logLevel`, and `accessLog`.

## GitHub Codespaces Quota

- GitHub provides limited monthly Codespaces compute.
- Stop your Codespace when not in use to preserve your hours.
- You can restart it later; the relay will reuse the same configured upstream URL.

## Troubleshooting

- **Container says `G2RAY_UPSTREAM_URL is not configured`:** set `upstreamUrl` in `.devcontainer/config.json`, or add the Codespaces secret/environment variable, then rebuild or restart the Codespace.
- **Client connects but no traffic flows:** verify the upstream Xray XHTTP path, UUID, and security settings.
- **TLS/SNI errors to upstream:** use an `https://` upstream URL whose hostname matches the upstream certificate.
- **404 or unexpected HTTP response:** confirm whether the upstream expects `/`, `/xhttp`, or another path and update the configured upstream URL accordingly.
- **Codespaces URL changes:** update your client with the latest forwarded port hostname shown by GitHub Codespaces.
- **Too many logs:** set `G2RAY_ACCESS_LOG=off` to disable request logging, or raise `G2RAY_LOG_LEVEL` to `warn` or `error` for less nginx diagnostic output.
- **Need request tracing:** leave `G2RAY_ACCESS_LOG=on`; each request log includes `request_id`, upstream status, and upstream response timing as JSON fields.

## Support the Project

If you find this project useful, consider supporting its development:

### Cryptocurrency Donations

- **Bitcoin**: `bc1qdwdpeqv0l8ala8tm46rtfeghuxl70een84npj3`
- **Ethereum**: `0x695CCF873d51E4C2dC1321b405C63BFE99c5a536`
- **Solana**: `C2d9u9nY2hZfxsi5Fwz1o5VjGGQujWmxeqZ3upKvHBfD`
- **TON Coin**: `UQAjStDMoMUusqRAuQGZ0Qbc2Th45yUUMdKlbhQ_6aS2TWlD`
- [Buy me a coffee ☕](https://www.buymeacoffee.com/amiremohamadi) (donate to the main REPO, he made it happen)

## Disclaimer

This tool is provided for educational and legitimate use only. Users are responsible for complying with their local laws, GitHub's policies, and their upstream provider's policies. The author is not responsible for misuse or legal consequences arising from this tool.

## License

This project is open-source. Please check the LICENSE file for details.
