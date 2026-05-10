param(
    [Parameter(Mandatory = $true)]
    [string]$Organization,
    [string]$Authentication = "azcli",
    [string[]]$Domains = @(),
    [switch]$ConfigureCodex,
    [switch]$ConfigureClaude,
    [switch]$ConfigureVSCode,
    [switch]$AllClients,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function ConvertTo-TomlString {
    param([string]$Value)
    return '"' + ($Value -replace '\\', '\\' -replace '"', '\"') + '"'
}

function Get-McpServerJson {
    param([string]$LauncherPath)

    return [ordered]@{
        type = "stdio"
        command = "powershell.exe"
        args = @(
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            $LauncherPath
        )
    }
}

function Merge-VSCodeMcpServer {
    param(
        [string]$Path,
        [string]$LauncherPath
    )

    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null

    if (Test-Path -LiteralPath $Path) {
        $raw = Get-Content -LiteralPath $Path -Raw
        $json = if ([string]::IsNullOrWhiteSpace($raw)) { [pscustomobject]@{} } else { $raw | ConvertFrom-Json }
    } else {
        $json = [pscustomobject]@{}
    }

    if ($null -eq $json.PSObject.Properties["servers"]) {
        $json | Add-Member -NotePropertyName "servers" -NotePropertyValue ([pscustomobject]@{})
    }

    $servers = $json.servers
    $server = Get-McpServerJson -LauncherPath $LauncherPath

    if ($null -ne $servers.PSObject.Properties["azure-devops"] -and -not $Force) {
        Write-Host "VS Code user MCP already has azure-devops. Use -Force to replace it."
        return
    }

    if ($null -ne $servers.PSObject.Properties["azure-devops"]) {
        $servers.PSObject.Properties.Remove("azure-devops")
    }

    $servers | Add-Member -NotePropertyName "azure-devops" -NotePropertyValue $server
    $json | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding utf8
    Write-Host "Configured VS Code user MCP: $Path"
}

$configureAll = $AllClients.IsPresent -or (-not $ConfigureCodex -and -not $ConfigureClaude -and -not $ConfigureVSCode)

$userHome = if ([string]::IsNullOrWhiteSpace($env:ADO_MCP_HOME)) { $HOME } else { $env:ADO_MCP_HOME }
$adoHome = Join-Path $userHome ".ado-mcp"
$launcherTarget = Join-Path $adoHome "ado-mcp.ps1"
$configTarget = Join-Path $adoHome "config.json"
$repoRoot = Split-Path -Parent $PSScriptRoot
$launcherSource = Join-Path $repoRoot "scripts\ado-mcp-launcher.ps1"

New-Item -ItemType Directory -Force -Path $adoHome | Out-Null
Copy-Item -LiteralPath $launcherSource -Destination $launcherTarget -Force

if ((Test-Path -LiteralPath $configTarget) -and -not $Force) {
    Write-Host "User Azure DevOps MCP config already exists: $configTarget"
    Write-Host "Use -Force to replace it."
} else {
    $config = [ordered]@{
        organization = $Organization
        authentication = $Authentication
    }

    if ($Domains.Count -gt 0) {
        $config.domains = $Domains
    }

    $config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $configTarget -Encoding utf8
    Write-Host "Wrote user Azure DevOps MCP config: $configTarget"
}

if ($configureAll -or $ConfigureCodex) {
    $codexConfigDir = Join-Path $userHome ".codex"
    $codexConfigPath = Join-Path $codexConfigDir "config.toml"
    New-Item -ItemType Directory -Force -Path $codexConfigDir | Out-Null

    $codexBlock = @"

[mcp_servers.azure-devops]
command = "powershell.exe"
args = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $(ConvertTo-TomlString -Value $launcherTarget)]
"@

    $existingCodex = if (Test-Path -LiteralPath $codexConfigPath) { Get-Content -LiteralPath $codexConfigPath -Raw } else { "" }
    if ($existingCodex -match '(?m)^\[mcp_servers\.azure-devops\]' -and -not $Force) {
        Write-Host "Codex user config already has azure-devops. Use -Force to replace it manually."
    } else {
        if ($existingCodex -match '(?m)^\[mcp_servers\.azure-devops\]') {
            throw "Codex config replacement is intentionally not automated. Remove the existing azure-devops block or edit $codexConfigPath."
        }

        Add-Content -LiteralPath $codexConfigPath -Value $codexBlock -Encoding utf8
        Write-Host "Configured Codex user MCP: $codexConfigPath"
    }
}

if ($configureAll -or $ConfigureVSCode) {
    $vsCodeMcpPath = Join-Path $env:APPDATA "Code\User\mcp.json"
    Merge-VSCodeMcpServer -Path $vsCodeMcpPath -LauncherPath $launcherTarget
}

if ($configureAll -or $ConfigureClaude) {
    $claude = Get-Command "claude" -ErrorAction SilentlyContinue
    if ($null -eq $claude) {
        Write-Host "Claude CLI was not found. Run this after installing Claude Code:"
        Write-Host "claude mcp add --scope user azure-devops -- powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$launcherTarget`""
    } else {
        & claude mcp add --scope user azure-devops -- powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcherTarget
        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }
    }
}

Write-Host ""
Write-Host "Setup complete. Authentication defaults to azcli (your logged-in Azure CLI account)."
Write-Host "Run 'az login' if you have not already authenticated."
Write-Host "To use a service principal instead, set AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, and AZURE_TENANT_ID"
Write-Host "as user environment variables, then restart Codex, Claude Code, and VS Code."
