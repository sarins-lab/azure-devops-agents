param(
    [string[]]$Clients   = @("All"),
    [switch]$PurgeGlobal
)

$ErrorActionPreference = "Stop"

$configureCodex  = $false
$configureClaude = $false
$configureVSCode = $false

foreach ($client in $Clients) {
    switch ($client.Trim().ToLower()) {
        "all"                       { $configureCodex = $true; $configureClaude = $true; $configureVSCode = $true }
        "codex"                     { $configureCodex  = $true }
        "claude"                    { $configureClaude = $true }
        { $_ -in "vscode","vs-code","copilot" } { $configureVSCode = $true }
        ""                          { }
        default                     { throw "Unknown client: $client" }
    }
}

$userHome = if ([string]::IsNullOrWhiteSpace($env:ADO_MCP_HOME)) { $HOME } else { $env:ADO_MCP_HOME }
$adoHome  = Join-Path $userHome ".ado-mcp"

function Remove-MarkdownBlock {
    param([string]$Path, [string]$Marker)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $start = "<!-- ${Marker}: start -->"
    $end   = "<!-- ${Marker}: end -->"
    $text  = Get-Content -LiteralPath $Path -Raw
    if (-not $text.Contains($start)) {
        Write-Host "  Block not found, nothing to remove: $Path"
        return
    }
    $escapedStart = [regex]::Escape($start)
    $escapedEnd   = [regex]::Escape($end)
    $text = [regex]::Replace($text, "`n?$escapedStart[\s\S]*?$escapedEnd`n?", "`n")
    $text = [regex]::Replace($text, "`n{3,}", "`n`n").TrimEnd() + "`n"
    Set-Content -LiteralPath $Path -Value $text -NoNewline
    Write-Host "  Removed block from: $Path"
}

function Get-VSCodeUserDir {
    if ($IsWindows -or $env:OS -eq "Windows_NT") {
        return Join-Path $env:APPDATA "Code\User"
    }
    if ($IsMacOS) {
        return Join-Path $HOME "Library/Application Support/Code/User"
    }
    $xdg = $env:XDG_CONFIG_HOME
    if ([string]::IsNullOrWhiteSpace($xdg)) { $xdg = Join-Path $HOME ".config" }
    return Join-Path $xdg "Code/User"
}

# ── Claude Code ────────────────────────────────────────────────────────────────
if ($configureClaude) {
    Write-Host "Removing Claude Code configuration..."

    $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($claudeCmd) {
        $mcpList = & claude mcp list 2>$null
        if ($mcpList -match "azure-devops") {
            & claude mcp remove --scope user azure-devops
            Write-Host "  Removed MCP server: azure-devops"
        } else {
            Write-Host "  MCP server not registered, skipping."
        }

        $pluginList = & claude plugin list 2>$null
        if ($pluginList -match "azure-devops-agents-claude@azure-devops-agents") {
            & claude plugin uninstall --scope user azure-devops-agents-claude@azure-devops-agents
            Write-Host "  Uninstalled plugin: azure-devops-agents-claude"
        } else {
            Write-Host "  Plugin not installed, skipping."
        }

        $marketplaceList = & claude plugin marketplace list 2>$null
        if ($marketplaceList -match "azure-devops-agents") {
            & claude plugin marketplace remove --scope user azure-devops-agents
            Write-Host "  Removed marketplace: azure-devops-agents"
        } else {
            Write-Host "  Marketplace not registered, skipping."
        }
    } else {
        Write-Host "  Claude CLI not found — skipping MCP/plugin removal."
    }

    Remove-MarkdownBlock -Path (Join-Path $userHome ".claude\CLAUDE.md") -Marker "azure-devops-agents"
}

# ── VS Code / Copilot ──────────────────────────────────────────────────────────
if ($configureVSCode) {
    Write-Host "Removing VS Code configuration..."
    $vsCodeDir    = Get-VSCodeUserDir
    $mcpPath      = Join-Path $vsCodeDir "mcp.json"
    $settingsPath = Join-Path $vsCodeDir "settings.json"
    $copilotCtx   = Join-Path $adoHome "copilot-context.md"
    $promptDir    = Join-Path $adoHome "prompts"

    if (Test-Path -LiteralPath $mcpPath) {
        $mcp = Get-Content -LiteralPath $mcpPath -Raw | ConvertFrom-Json
        if ($mcp.servers -and $mcp.servers.PSObject.Properties["azure-devops"]) {
            $mcp.servers.PSObject.Properties.Remove("azure-devops")
            $mcp | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $mcpPath
            Write-Host "  Removed azure-devops from: $mcpPath"
        } else {
            Write-Host "  azure-devops not found in: $mcpPath"
        }
    } else {
        Write-Host "  VS Code mcp.json not found, skipping."
    }

    if (Test-Path -LiteralPath $settingsPath) {
        $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
        $instructionKey = "github.copilot.chat.codeGeneration.instructions"
        $prop = $settings.PSObject.Properties[$instructionKey]
        if ($prop -and $prop.Value -is [array]) {
            $filtered = @($prop.Value | Where-Object { $_.file -ne $copilotCtx })
            if ($filtered.Count -eq 0) {
                $settings.PSObject.Properties.Remove($instructionKey)
            } else {
                $settings.$instructionKey = $filtered
            }
        }
        $promptKey = "chat.promptFilesLocations"
        $promptProp = $settings.PSObject.Properties[$promptKey]
        if ($promptProp -and $promptProp.Value -is [psobject]) {
            $promptProp.Value.PSObject.Properties.Remove($promptDir)
            if ($promptProp.Value.PSObject.Properties.Count -eq 0) {
                $settings.PSObject.Properties.Remove($promptKey)
            }
        }
        $settings | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $settingsPath
        Write-Host "  Updated VS Code settings: $settingsPath"
    } else {
        Write-Host "  VS Code settings.json not found, skipping."
    }

    if (Test-Path -LiteralPath $copilotCtx) { Remove-Item -LiteralPath $copilotCtx -Force; Write-Host "  Removed: $copilotCtx" }
    if (Test-Path -LiteralPath $promptDir)  { Remove-Item -LiteralPath $promptDir -Recurse -Force; Write-Host "  Removed: $promptDir" }
}

# ── Codex ──────────────────────────────────────────────────────────────────────
if ($configureCodex) {
    Write-Host "Removing Codex configuration..."
    $codexToml = Join-Path $userHome ".codex\config.toml"

    if (Test-Path -LiteralPath $codexToml) {
        $text = Get-Content -LiteralPath $codexToml -Raw
        if ($text -match '\[mcp_servers\.azure-devops\]') {
            $text = [regex]::Replace($text, "`n?\[mcp_servers\.azure-devops\]\r?\n[\s\S]*?(?=\n\[|\s*$)", "")
            Set-Content -LiteralPath $codexToml -Value $text -NoNewline
            Write-Host "  Removed [mcp_servers.azure-devops] from: $codexToml"
        } else {
            Write-Host "  [mcp_servers.azure-devops] not found in: $codexToml"
        }
    } else {
        Write-Host "  Codex config.toml not found, skipping."
    }

    Remove-MarkdownBlock -Path (Join-Path $userHome ".codex\AGENTS.md") -Marker "azure-devops-agents"
}

# ── Shared ~/.ado-mcp directory ────────────────────────────────────────────────
if ($configureClaude -and $configureVSCode -and $configureCodex) {
    if (Test-Path -LiteralPath $adoHome) {
        Remove-Item -LiteralPath $adoHome -Recurse -Force
        Write-Host "Removed: $adoHome"
    }
}

# ── Optional: global npm package ──────────────────────────────────────────────
if ($PurgeGlobal) {
    if (Get-Command mcp-server-azuredevops -ErrorAction SilentlyContinue) {
        & npm uninstall -g @azure-devops/mcp
        Write-Host "Uninstalled global package: @azure-devops/mcp"
    } else {
        Write-Host "Global package not installed, skipping."
    }
}

Write-Host ""
Write-Host "Done. Uninstall complete."
