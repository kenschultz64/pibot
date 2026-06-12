param(
  [string]$Name = "pibot",
  [string]$HostPort = "11436",
  [string]$BindHost = "127.0.0.1",
  [string]$PublicBaseUrl = "http://127.0.0.1:11436",
  [string]$Image = "pibot:latest",
  [string]$PiAgentDir = "$env:USERPROFILE\.pi\agent",
  [string]$PiTools = "read,bash,edit,write,grep,find,ls"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

if (!(Test-Path ".\.bridge-key")) {
  "pi-$([guid]::NewGuid().ToString('N'))" | Set-Content ".\.bridge-key"
  Write-Host "Created .bridge-key"
}

if (!(Test-Path ".\.file-key")) {
  "file-$([guid]::NewGuid().ToString('N'))" | Set-Content ".\.file-key"
  Write-Host "Created .file-key"
}

$bridgeKey = (Get-Content ".\.bridge-key" -Raw).Trim()
$fileKey = (Get-Content ".\.file-key" -Raw).Trim()

Write-Host "Building $Image..."
docker build -f Dockerfile.pi-bridge -t $Image .

Write-Host "Removing old $Name container if present..."
docker rm -f $Name 2>$null | Out-Null

Write-Host "Starting $Name on ${BindHost}:${HostPort}..."
docker run -d `
  --name $Name `
  --restart unless-stopped `
  --user node `
  --cap-drop=ALL `
  --security-opt no-new-privileges:true `
  -p "${BindHost}:${HostPort}:11435" `
  -e PI_BRIDGE_API_KEY="$bridgeKey" `
  -e PI_FILE_DOWNLOAD_KEY="$fileKey" `
  -e PI_PUBLIC_BASE_URL="$PublicBaseUrl" `
  -e PI_WORKSPACE="/workspace" `
  -e PI_TOOLS="$PiTools" `
  -e HOME="/home/node" `
  -v "${Name}-workspace:/workspace" `
  -v "${PiAgentDir}:/home/node/.pi/agent:ro" `
  $Image | Out-Host

Write-Host ""
Write-Host "Open WebUI Base URL: $PublicBaseUrl/v1"
Write-Host "Open WebUI API Key: contents of .bridge-key"
Write-Host "Container workspace: /workspace"
Write-Host "Bound host interface: $BindHost"
Write-Host "Pi auth/config mount: $PiAgentDir -> /home/node/.pi/agent:ro"
