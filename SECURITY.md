# Security hardening guide

PiBot is designed to let Open WebUI talk to a Pi coding-agent session. If you enable `bash`, `write`, or `edit`, treat access to the PiBot API key as equivalent to shell access inside the bot container.

The Docker launch scripts in this repo use safer defaults while preserving the normal bot workflow:

- Bind the bridge to a chosen interface instead of every network interface.
- Keep shell tools enabled by default for useful coding-agent behavior.
- Run the container as the unprivileged `node` user.
- Mount Pi auth/config read-only.
- Drop default Linux capabilities and enable `no-new-privileges`.
- Keep the root filesystem writable so normal tools, caches, and temporary files keep working.

## Recommended network binding

Do not publish PiBot on the public internet. Bind it only where Open WebUI can reach it.

Local-only Open WebUI:

```bash
BIND_HOST=127.0.0.1 HOST_PORT=11436 ./start-pibot-docker.sh
```

Tailscale/Open WebUI on another trusted machine:

```bash
BIND_HOST=100.x.y.z HOST_PORT=11436 PI_PUBLIC_BASE_URL=http://100.x.y.z:11436 ./start-pibot-docker.sh
```

Open WebUI should then use:

```text
Base URL: http://100.x.y.z:11436/v1
API Key: contents of .bridge-key
```

## Shell tools

The default tool list is intentionally useful:

```text
read,bash,edit,write,grep,find,ls
```

If you want a read-only bot, set:

```bash
PI_TOOLS=read,grep,find,ls ./start-pibot-docker.sh
```

If shell execution is enabled, keep the bridge private and protect `.bridge-key`.

## Pi auth/config mount

The hardened launchers mount your Pi agent config read-only:

```text
$HOME/.pi/agent:/home/node/.pi/agent:ro
```

This lets PiBot read model/provider configuration without allowing the container to rewrite those files. If Pi needs to update auth state, stop the hardened container, update auth from your normal host Pi setup, then restart PiBot.

For higher isolation, use a dedicated Pi agent config directory containing only the provider/model credentials needed by this bridge.

## Docker hardening flags

The launchers include:

```text
--user node
--cap-drop=ALL
--security-opt no-new-privileges:true
```

These preserve normal workspace shell usage but remove broad container privileges. If a future use case needs a specific Linux capability, add that one explicitly instead of removing all hardening.

## Verification

After starting PiBot, verify:

```bash
# Unauthenticated request should fail with 401
curl -i http://HOST:PORT/v1/models

# Authenticated request should succeed.
# Replace API_KEY_HERE with the contents of .bridge-key.
curl -i "http://HOST:PORT/v1/models?key=API_KEY_HERE"

# Container should be non-root
docker exec pibot id

# Pi auth mount should be read-only
docker exec pibot bash -lc 'echo test >> /home/node/.pi/agent/auth.json'
```

The final command should fail with a read-only filesystem error.
