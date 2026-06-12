# PiBot - Docker-first Pi bridge for Open WebUI

PiBot is an OpenAI-compatible HTTP bridge that lets **Open WebUI** talk to a headless **Pi coding-agent** session.

It exposes:

```text
GET  /v1/models
POST /v1/chat/completions
POST /webhook
GET  /files/<file>
```

Configure Open WebUI as an **OpenAI-compatible API**, not Ollama.

---

## Recommended setup: run PiBot in Docker

Running the bridge directly on Windows works, but Docker is safer for Open WebUI because the agent's shell/filesystem access is contained in a container workspace instead of your whole local machine.

With Docker:

- Pi tools run in `/workspace`, not your Windows home folder.
- Generated files persist in a Docker volume.
- The bridge can restart automatically with Docker.
- You can still mount your Pi model/auth settings so the container uses your normal Pi configuration.

---

## Quick start on Windows with Docker Desktop

From this folder in PowerShell:

```powershell
# 1. Create secrets if needed
if (!(Test-Path .\.bridge-key)) { "pi-$([guid]::NewGuid().ToString('N'))" | Set-Content .\.bridge-key }
if (!(Test-Path .\.file-key)) { "file-$([guid]::NewGuid().ToString('N'))" | Set-Content .\.file-key }

# 2. Build the image
docker build -f Dockerfile.pi-bridge -t pibot:latest .

# 3. Remove any old container
docker rm -f pibot 2>$null

# 4. Run PiBot
$bridgeKey = (Get-Content .\.bridge-key -Raw).Trim()
$fileKey = (Get-Content .\.file-key -Raw).Trim()

docker run -d `
  --name pibot `
  --restart unless-stopped `
  --user node `
  --cap-drop=ALL `
  --security-opt no-new-privileges:true `
  -p 127.0.0.1:11436:11435 `
  -e PI_BRIDGE_API_KEY="$bridgeKey" `
  -e PI_FILE_DOWNLOAD_KEY="$fileKey" `
  -e PI_PUBLIC_BASE_URL="http://127.0.0.1:11436" `
  -e PI_WORKSPACE="/workspace" `
  -e PI_TOOLS="read,bash,edit,write,grep,find,ls" `
  -e HOME="/home/node" `
  -v pibot-workspace:/workspace `
  -v "$env:USERPROFILE\.pi\agent:/home/node/.pi/agent:ro" `
  pibot:latest
```

If Open WebUI is on another machine or accessed over Tailscale, set `PI_PUBLIC_BASE_URL` to that reachable address, for example:

```powershell
-p 100.x.y.z:11436:11435
-e PI_PUBLIC_BASE_URL="http://100.x.y.z:11436"
```

The included launch scripts use these same hardened defaults. See [SECURITY.md](SECURITY.md) for the rationale and verification commands.

---

## Open WebUI settings

Use **OpenAI-compatible API**:

```text
Base URL: http://YOUR_HOST_OR_TAILSCALE_IP:11436/v1
API Key: contents of .bridge-key
Model: pi-agent
```

Copy the API key:

```powershell
Get-Content .\.bridge-key | Set-Clipboard
```

Do not choose Ollama for this bridge.

---

## Webhook relay

For simple integrations that do not send OpenAI-compatible chat payloads, PiBot also exposes a webhook endpoint:

```text
POST /webhook
Authorization: Bearer YOUR_BRIDGE_KEY
Content-Type: application/json

{
  "message": "Your prompt here",
  "context": "Optional extra context"
}
```

It returns:

```json
{
  "response": "Pi response text",
  "source": "Pi-Core-Relay"
}
```

---

## File downloads

When PiBot creates files, it should return links like:

```text
http://YOUR_HOST:11436/files/powerpoints/example.pptx?key=FILE_DOWNLOAD_KEY
```

The chat API key and file-download key are separate:

- `.bridge-key` authenticates Open WebUI to `/v1/*`.
- `.file-key` allows browser downloads from `/files/*`.

Files must be inside `/workspace` in the container. The recommended persistent location for projects and outputs is:

```text
/workspace/projects
/workspace/powerpoints
/workspace/files
```

---

## Verify the container

```powershell
docker ps --filter name=pibot
```

Health check:

```powershell
$key = (Get-Content .\.bridge-key -Raw).Trim()
curl.exe http://127.0.0.1:11436/health -H "Authorization: Bearer $key"
```

Container shell:

```powershell
docker exec -it pibot bash
```

List workspace:

```powershell
docker exec pibot ls -la /workspace
```

Logs:

```powershell
docker logs -f pibot
```

Stop/start:

```powershell
docker stop pibot
docker start pibot
```

---

## Installing dependencies or repos inside the container

Use a shell in the container:

```powershell
docker exec -it pibot bash
```

Examples:

```bash
cd /workspace/projects
git clone https://github.com/OWNER/REPO.git
cd REPO
npm install
# or
pip install -r requirements.txt
```

Anything under `/workspace` persists because it is a Docker volume. Avoid putting custom work under `/app`; that is part of the image and can be replaced when rebuilt.

For dependencies you always need, add them to `Dockerfile.pi-bridge` and rebuild.

---

## Pi model/settings used by Docker

The hardened Docker command mounts your existing Pi settings read-only:

```text
Windows: %USERPROFILE%\.pi\agent
Docker:  /home/node/.pi/agent
```

So model settings are still edited on Windows here:

```text
C:\Users\YOUR_USER\.pi\agent\models.json
C:\Users\YOUR_USER\.pi\agent\settings.json
```

Then restart the container:

```powershell
docker restart pibot
```

You may also force a provider/model with environment variables:

```text
PI_PROVIDER=provider-name
PI_MODEL=model-id
```

But the safest default is to let Pi use its configured/default model from `settings.json`.

---

## Custom instructions: AGENTS.md

Pi loads `AGENTS.md` or `CLAUDE.md` at startup from the workspace and parent folders, plus global instructions from `~/.pi/agent/AGENTS.md`.

Project instructions inside the Docker workspace:

```bash
cat > /workspace/AGENTS.md <<'EOF'
# Agent Instructions

Always use tools when creating or editing files.
Save PowerPoints in /workspace/powerpoints.
After creating a file, provide the workspace-relative path and download link.
EOF
```

Global instructions on Windows:

```text
C:\Users\YOUR_USER\.pi\agent\AGENTS.md
```

Restart after changing global/project instructions if needed:

```powershell
docker restart pibot
```

---

## Skills

Pi supports Agent Skills. Put project skills under:

```text
/workspace/.pi/skills/<skill-name>/SKILL.md
```

Example:

```bash
mkdir -p /workspace/.pi/skills/powerpoint-sermon
cat > /workspace/.pi/skills/powerpoint-sermon/SKILL.md <<'EOF'
---
name: powerpoint-sermon
description: Create sermon or Bible study PowerPoint presentations with title, scripture, teaching points, application, and closing slides.
---

# PowerPoint Sermon Skill

When asked to create a sermon, lesson, Bible study, or teaching PowerPoint:

1. Create the file under /workspace/powerpoints.
2. Use python-pptx unless asked otherwise.
3. Include title, scripture, main idea, teaching points, application, and closing slides.
4. Keep slides readable and uncluttered.
5. Provide the workspace-relative path and download link.
EOF
```

Then ask Open WebUI:

```text
Use the powerpoint-sermon skill to create a PowerPoint on James 4:1-12.
```

---

## Optional: run the bridge directly without Docker

Direct mode is useful for development, but it exposes the host machine's filesystem/tools to the agent if you enable full tools. Prefer Docker for Open WebUI.

Install and run:

```bash
npm install
npm start
```

Or use the included legacy start scripts:

```text
start-pi-openwebui-bridge.bat
start-pi-openwebui-bridge-hidden.bat
stop-pi-openwebui-bridge.bat
start-pi-openwebui-bridge.sh
start-pi-openwebui-bridge-hidden.sh
stop-pi-openwebui-bridge.sh
```

If running direct mode, bind carefully, use a strong `.bridge-key`, and expose it only to trusted networks.

---

## Environment variables

| Variable | Default | Description |
| --- | --- | --- |
| `PORT` | `11435` | Port inside the container/process |
| `HOST` | `127.0.0.1`; Dockerfile sets `0.0.0.0` | Bind host |
| `PI_WORKSPACE` | process cwd; Docker uses `/workspace` | Folder where Pi tools run |
| `PI_PUBLIC_BASE_URL` | `http://HOST:PORT` | Public URL used in generated download links |
| `PI_OPENWEBUI_MODEL` | `pi-agent` | Model name shown to Open WebUI |
| `PI_BRIDGE_API_KEY` | unset | Required bearer token for chat/model endpoints |
| `PI_FILE_DOWNLOAD_KEY` | unset | Optional separate key for browser file downloads |
| `PI_TOOLS` | read-only default in code; Docker uses full tools | Comma-separated Pi tools |
| `PI_SHOW_PROGRESS` | `true` | Stream progress messages such as tool start/end |
| `PI_PROVIDER` | unset | Optional provider override |
| `PI_MODEL` | unset | Optional model override |
| `BIND_HOST` | launcher default `127.0.0.1` | Docker launcher host interface to publish on; use a Tailscale IP for trusted remote Open WebUI |
| `PI_AGENT_DIR` | launcher default `$HOME/.pi/agent` | Host Pi config/auth directory mounted read-only into the container |

Tool examples:

```bash
PI_TOOLS=read,grep,find,ls
PI_TOOLS=read,bash,edit,write,grep,find,ls
PI_TOOLS=default
PI_TOOLS=none
```

---

## Troubleshooting Docker tool use

The host machine does **not** need Pi/Pi Coder installed when you run PiBot in Docker. The Docker image installs `@earendil-works/pi-coding-agent` inside the container.

If PiBot answers normally but does not seem to run shell/file commands, check these items:

- Start the container with full tools enabled if you want shell/file access:

  ```bash
  -e PI_TOOLS="read,bash,edit,write,grep,find,ls"
  ```

- Remember that commands run inside the container workspace, usually:

  ```text
  /workspace
  ```

  They do not run against the host filesystem unless you mount folders into the container.

- Mount your Pi agent config/auth if you want the container to use the same Pi provider/model setup as your host:

  ```bash
  -v "$HOME/.pi/agent:/home/node/.pi/agent:ro"
  ```

  On Windows PowerShell this is usually:

  ```powershell
  -v "$env:USERPROFILE\.pi\agent:/home/node/.pi/agent:ro"
  ```

- Rebuild after changing package files or server code:

  ```bash
  docker build --no-cache -f Dockerfile.pi-bridge -t pibot:latest .
  ```

Useful checks:

```bash
docker logs -f pibot
docker exec -it pibot bash
echo $PI_TOOLS
which pi
pi --version
ls -la /workspace
```

---

## Security notes

- Treat the bridge like remote shell access when `bash`, `edit`, or `write` tools are enabled.
- Prefer Docker for Open WebUI so tools are contained to `/workspace`.
- Bind the published Docker port to `127.0.0.1` or a trusted Tailscale/VPN IP, not every interface.
- Run as a non-root container user when possible.
- Mount Pi auth/config read-only.
- Use Docker hardening such as `--cap-drop=ALL` and `--security-opt no-new-privileges:true`.
- Do not commit `.bridge-key` or `.file-key`.
- Use Tailscale/VPN/firewall rules where possible.
- Rotate keys if they are pasted into chat, logs, screenshots, or documentation.
- See [SECURITY.md](SECURITY.md) for the full hardening guide.

---

## Credits & Attribution

This project is an independent wrapper and is not officially affiliated with Earendil Works.

- **Core Engine:** Built using `@earendil-works/pi-agent-core` and `@earendil-works/pi-ai` under the MIT License.
- **Shoutout:** Huge thanks to Mario Zechner and the Earendil Works contributors for creating Pi!
- **License:** This endpoint wrapper is released under the MIT License. See [NOTICE.md](NOTICE.md) for the Pi core engine MIT notice, including `Copyright (c) 2025 Mario Zechner / Earendil Works`.

---

## Support

If this project helps you, you can support it here:
[![Buy Me A Coffee](https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png)](https://www.buymeacoffee.com/gogospelnow)
https://www.buymeacoffee.com/gogospelnow
