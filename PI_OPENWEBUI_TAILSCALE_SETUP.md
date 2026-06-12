# PiBot Docker + Open WebUI over Tailscale

This setup assumes Open WebUI reaches PiBot over Tailscale.

## Recommended architecture

```text
Open WebUI  ->  http://TAILSCALE_IP:11436/v1  ->  PiBot Docker container  ->  Pi coding agent
```

Run PiBot in Docker rather than directly on Windows when possible. Docker keeps agent file and shell access inside `/workspace` instead of exposing your Windows filesystem.

## 1. Find the Windows/Tailscale IP

On the Windows machine running Docker Desktop:

```powershell
tailscale ip -4
```

Example:

```text
100.x.y.z
```

## 2. Create keys

From the PiBot folder:

```powershell
if (!(Test-Path .\.bridge-key)) { "pi-$([guid]::NewGuid().ToString('N'))" | Set-Content .\.bridge-key }
if (!(Test-Path .\.file-key)) { "file-$([guid]::NewGuid().ToString('N'))" | Set-Content .\.file-key }
```

- `.bridge-key` is the Open WebUI API key.
- `.file-key` is only for browser file downloads.

Do not paste real keys into documentation or screenshots.

## 3. Build and run Docker container

Replace `100.x.y.z` with your Tailscale IP. The launcher builds the image, starts the container as a non-root user, binds only to the Tailscale IP, mounts Pi config read-only, and applies Docker hardening flags.

```powershell
.\start-pibot-docker.ps1 `
  -BindHost "100.x.y.z" `
  -PublicBaseUrl "http://100.x.y.z:11436"
```

Equivalent hardening flags used by the launcher:

```text
--user node
--cap-drop=ALL
--security-opt no-new-privileges:true
-p 100.x.y.z:11436:11435
-v <your Pi agent dir>:/home/node/.pi/agent:ro
```

## 4. Test from Windows

```powershell
$key = (Get-Content .\.bridge-key -Raw).Trim()
curl.exe "http://100.x.y.z:11436/v1/models?key=$key"
```

## 5. Test from Open WebUI host/container

From the host running Open WebUI:

```bash
curl "http://100.x.y.z:11436/v1/models?key=YOUR_BRIDGE_KEY"
```

If Open WebUI is in Docker, test from inside that container too:

```bash
docker exec -it open-webui curl "http://100.x.y.z:11436/v1/models?key=YOUR_BRIDGE_KEY"
```

If the host works but the Open WebUI container fails, the Open WebUI container cannot route to Tailscale. Fix Docker networking or run PiBot on the same host as Open WebUI.

## 6. Configure Open WebUI

```text
Connection type: OpenAI-compatible API
Base URL: http://100.x.y.z:11436/v1
API Key: contents of .bridge-key
Model: pi-agent
```

## 7. File downloads

Generated file links use `.file-key`, for example:

```text
http://100.x.y.z:11436/files/powerpoints/example.pptx?key=YOUR_FILE_KEY
```

If a generated link fails:

1. Verify the file exists in the container:

   ```powershell
   docker exec pibot find /workspace -maxdepth 3 -type f
   ```

2. Verify `PI_PUBLIC_BASE_URL` points to the reachable Tailscale URL.
3. Verify the link includes `?key=<contents of .file-key>`.

## 8. Firewall

If other Tailscale devices cannot connect, allow the published port:

```powershell
New-NetFirewallRule `
  -DisplayName "PiBot 11436" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 11436 `
  -Action Allow `
  -Profile Any
```

## 9. Useful commands

```powershell
docker ps --filter name=pibot
docker logs -f pibot
docker exec -it pibot bash
docker restart pibot
docker stop pibot
```

## 10. Troubleshooting shell/tool use

The host machine does **not** need Pi/Pi Coder installed. The Docker image installs `@earendil-works/pi-coding-agent` inside the container.

If PiBot responds but does not run shell/file commands, verify:

- The container was started with full tools enabled:

  ```powershell
  -e PI_TOOLS="read,bash,edit,write,grep,find,ls"
  ```

- Commands run inside `/workspace`, not directly on the host filesystem.
- Your Pi auth/config is mounted if needed:

  ```powershell
  -v "$env:USERPROFILE\.pi\agent:/home/node/.pi/agent:ro"
  ```

- The image was rebuilt after changes:

  ```powershell
  docker build --no-cache -f Dockerfile.pi-bridge -t pibot:latest .
  ```

Inside the container, check:

```bash
echo $PI_TOOLS
which pi
pi --version
ls -la /workspace
```

## 11. Legacy direct bridge mode

The non-Docker bridge scripts still work, but direct mode exposes the host workspace to the agent when tools are enabled. Use direct mode only for trusted local development.

## Credits & Attribution

This project is an independent wrapper and is not officially affiliated with Earendil Works. It is built using `@earendil-works/pi-agent-core` and `@earendil-works/pi-ai` under the MIT License. Huge thanks to Mario Zechner and the Earendil Works contributors for creating Pi. This endpoint wrapper is released under the MIT License; see `NOTICE.md` for the core engine's copyright notice.
