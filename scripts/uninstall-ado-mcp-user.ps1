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

# VS Code settings.json is JSONC — strip comments/trailing commas before parsing.
function Remove-JsonCommentsAndTrailingCommas {
    param([string]$Content)
    $sb = [System.Text.StringBuilder]::new()
    $inString = $false; $escaped = $false
    $inLineComment = $false; $inBlockComment = $false
    for ($i = 0; $i -lt $Content.Length; $i++) {
        $ch = $Content[$i]
        $next = if ($i + 1 -lt $Content.Length) { $Content[$i + 1] } else { [char]0 }
        if ($inLineComment) {
            if ($ch -eq "`r" -or $ch -eq "`n") { $inLineComment = $false; [void]$sb.Append($ch) }
            continue
        }
        if ($inBlockComment) {
            if ($ch -eq "*" -and $next -eq "/") { $inBlockComment = $false; $i++ }
            continue
        }
        if ($inString) {
            [void]$sb.Append($ch)
            if ($escaped) { $escaped = $false } elseif ($ch -eq "\") { $escaped = $true } elseif ($ch -eq '"') { $inString = $false }
            continue
        }
        if ($ch -eq "/" -and $next -eq "/") { $inLineComment = $true; continue }
        if ($ch -eq "/" -and $next -eq "*") { $inBlockComment = $true; $i++; continue }
        if ($ch -eq '"') { $inString = $true }
        [void]$sb.Append($ch)
    }
    return [regex]::Replace($sb.ToString(), ',\s*([}\]])', '$1')
}

function ConvertFrom-JsonOrJsonC {
    param([string]$Content, [string]$Path)
    try { return $Content | ConvertFrom-Json }
    catch {
        try { return (Remove-JsonCommentsAndTrailingCommas -Content $Content) | ConvertFrom-Json }
        catch { throw "Unable to parse JSONC file '$Path': $($_.Exception.Message)" }
    }
}

function Backup-FileBeforeJsonRewrite {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $backupPath = "$Path.ado-mcp.$(Get-Date -Format 'yyyyMMddHHmmssfff').bak"
    Copy-Item -LiteralPath $Path -Destination $backupPath -Force
    Write-Host "  Backed up file before JSON rewrite: $backupPath"
}

function Remove-ClaudeUserMcpServer {
    param(
        [string]$SuccessMessage,
        [string]$NotFoundMessage,
        [string]$FailureMessage
    )

    $listOutput = (& claude mcp list 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0) {
        if (-not [string]::IsNullOrWhiteSpace($listOutput)) {
            Write-Warning $listOutput
        }
        Write-Warning $FailureMessage
        return
    }

    $removed = $false
    $failed = $false
    foreach ($line in ($listOutput -split "`r?`n")) {
        if ($line -notmatch '\.ado-mcp[\\/](ado-mcp|ado-mcp-launcher)\.(sh|ps1)') {
            continue
        }

        $colonIndex = $line.IndexOf(':')
        if ($colonIndex -lt 0) {
            continue
        }

        $name = $line.Substring(0, $colonIndex).Trim()
        if ([string]::IsNullOrWhiteSpace($name)) {
            continue
        }

        $output = (& claude mcp remove --scope user $name 2>&1) -join "`n"
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Removed standalone Claude MCP server: $name"
            $removed = $true
            continue
        }

        if ($output -match [regex]::Escape("No user-scoped MCP server found with name: $name")) {
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($output)) {
            Write-Warning $output
        }
        $failed = $true
    }

    if ($failed) {
        Write-Warning $FailureMessage
        return
    }

    if ($removed) {
        Write-Host $SuccessMessage
    } else {
        Write-Host $NotFoundMessage
    }
}

function Get-NpmCommandPath {
    $npmCmd = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if ($npmCmd) {
        return $npmCmd.Source
    }

    $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
    if ($npmCmd) {
        return $npmCmd.Source
    }

    return $null
}

function Remove-MarkdownBlock {
    param([string]$Path, [string]$Marker)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $start = "<!-- ${Marker}: start -->"
    $end   = "<!-- ${Marker}: end -->"
    # Normalise CRLF so the regex works regardless of line endings.
    $text = (Get-Content -LiteralPath $Path -Raw) -replace "`r`n", "`n"
    if (-not $text.Contains($start)) {
        Write-Host "  Block not found, nothing to remove: $Path"
        return
    }
    $escapedStart = [regex]::Escape($start)
    $escapedEnd   = [regex]::Escape($end)
    $text = [regex]::Replace($text, "`n?$escapedStart[\s\S]*?$escapedEnd`n?", "`n")
    $text = [regex]::Replace($text, "`n{3,}", "`n`n").TrimEnd() + "`n"
    Set-Content -LiteralPath $Path -Value $text -Encoding utf8 -NoNewline
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
        Remove-ClaudeUserMcpServer `
            -SuccessMessage "  Removed standalone Claude MCP server registrations." `
            -NotFoundMessage "  Standalone Claude MCP servers not registered, skipping." `
            -FailureMessage "Could not remove standalone Claude MCP server registrations."

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

    # Remove the disabledMcpjsonServers entry added by the installer.
    $claudeSettingsPath = Join-Path $userHome ".claude\settings.json"
    if (Test-Path -LiteralPath $claudeSettingsPath) {
        try {
            $raw  = Get-Content -LiteralPath $claudeSettingsPath -Raw
            $json = if ([string]::IsNullOrWhiteSpace($raw)) { $null } else { $raw | ConvertFrom-Json }
            if ($null -ne $json) {
                $prop = $json.PSObject.Properties["disabledMcpjsonServers"]
                if ($null -ne $prop) {
                    $filtered = @($prop.Value | Where-Object { $_ -ne "azure-devops" })
                    if ($filtered.Count -eq 0) {
                        $json.PSObject.Properties.Remove("disabledMcpjsonServers")
                    } else {
                        $prop.Value = $filtered
                    }
                    $json | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $claudeSettingsPath -Encoding utf8
                    Write-Host "  Removed 'azure-devops' from disabledMcpjsonServers: $claudeSettingsPath"
                } else {
                    Write-Host "  disabledMcpjsonServers not present, skipping: $claudeSettingsPath"
                }
            }
        } catch {
            Write-Warning "Could not update $claudeSettingsPath - remove disabledMcpjsonServers manually. $($_.Exception.Message)"
        }
    } else {
        Write-Host "  Claude settings.json not found, skipping."
    }
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
        try {
            $mcp = Get-Content -LiteralPath $mcpPath -Raw | ConvertFrom-Json
            if ($mcp.servers -and $mcp.servers.PSObject.Properties["azure-devops"]) {
                $mcp.servers.PSObject.Properties.Remove("azure-devops")
                $mcp | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $mcpPath -Encoding utf8
                Write-Host "  Removed azure-devops from: $mcpPath"
            } else {
                Write-Host "  azure-devops not found in: $mcpPath"
            }
        } catch {
            Write-Warning "Could not parse $mcpPath - skipping MCP update. Remove azure-devops manually. $($_.Exception.Message)"
        }
    } else {
        Write-Host "  VS Code mcp.json not found, skipping."
    }

    if (Test-Path -LiteralPath $settingsPath) {
        try {
            $settings = ConvertFrom-JsonOrJsonC -Content (Get-Content -LiteralPath $settingsPath -Raw) -Path $settingsPath
            $changed = $false
            $instructionKey = "github.copilot.chat.codeGeneration.instructions"
            $prop = $settings.PSObject.Properties[$instructionKey]
            if ($prop -and $prop.Value -is [array]) {
                $current = @($prop.Value)
                $filtered = @($current | Where-Object { $_.file -ne $copilotCtx })
                if ($filtered.Count -ne $current.Count) {
                    $changed = $true
                    if ($filtered.Count -eq 0) {
                        $settings.PSObject.Properties.Remove($instructionKey)
                    } else {
                        $settings.$instructionKey = $filtered
                    }
                }
            }
            $promptKey = "chat.promptFilesLocations"
            $promptProp = $settings.PSObject.Properties[$promptKey]
            if ($promptProp -and $promptProp.Value -is [psobject]) {
                if ($promptProp.Value.PSObject.Properties[$promptDir]) {
                    $promptProp.Value.PSObject.Properties.Remove($promptDir)
                    $changed = $true
                    if ($promptProp.Value.PSObject.Properties.Count -eq 0) {
                        $settings.PSObject.Properties.Remove($promptKey)
                    }
                }
            }
            if ($changed) {
                Backup-FileBeforeJsonRewrite -Path $settingsPath
                $settings | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $settingsPath -Encoding utf8
                Write-Host "  Updated VS Code settings: $settingsPath"
            } else {
                Write-Host "  VS Code settings already clean: $settingsPath"
            }
        } catch {
            Write-Warning "Could not parse $settingsPath - skipping settings update. Remove azure-devops entries manually. $($_.Exception.Message)"
        }
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
            Set-Content -LiteralPath $codexToml -Value $text -Encoding utf8 -NoNewline
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
    $npmCommandPath = Get-NpmCommandPath
    if (-not $npmCommandPath) {
        Write-Warning "npm not found — cannot uninstall global package."
    } else {
        & $npmCommandPath uninstall -g "@azure-devops/mcp"
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Removed global package if present: @azure-devops/mcp"
        } else {
            Write-Warning "Global npm uninstall failed for @azure-devops/mcp (exit $LASTEXITCODE)."
        }
    }
}

Write-Host ""
Write-Host "Done. Uninstall complete."
