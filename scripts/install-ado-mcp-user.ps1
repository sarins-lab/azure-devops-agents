param(
    [Parameter(Mandatory = $true)]
    [string]$Organization,
    [ValidateSet("npx", "docker")]
    [string]$Mode = "npx",          # npx (default, recommended) or docker (experimental)
    [string]$Authentication = "azcli",
    [string[]]$Domains = @("core", "work", "work-items", "repositories", "wiki"),
    [string]$Project = $env:ADO_MCP_PROJECT,
    [string]$Team = $env:ADO_MCP_TEAM,
    [string]$DockerImage = "",      # Required when -Mode docker
    [string]$AuthToken = "",        # Optional PAT to persist as ADO_MCP_AUTH_TOKEN for Docker mode
    [switch]$ConfigureCodex,
    [switch]$ConfigureClaude,
    [switch]$ConfigureVSCode,
    [switch]$AllClients,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# -- Context inputs -------------------------------------------------------------
# Loaded from shared/ and plugins/ after the repo root is resolved.

# -- Helpers --------------------------------------------------------------------

function Read-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $content = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($content)) {
        return $null
    }

    return $content | ConvertFrom-Json
}

function Read-TextFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Required install artifact not found: $Path"
    }

    return Get-Content -LiteralPath $Path -Raw
}

function Join-TextSections {
    param([string[]]$Sections)

    $nonEmptySections = @()
    foreach ($section in $Sections) {
        if (-not [string]::IsNullOrWhiteSpace($section)) {
            $nonEmptySections += $section.Trim()
        }
    }

    return [string]::Join("`n`n", $nonEmptySections)
}

function Get-StringValue {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        return $null
    }

    $value = [string]$property.Value
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $null
    }

    return $value
}

function ConvertTo-TomlString {
    param([string]$Value)
    return '"' + ($Value -replace '\\', '\\' -replace '"', '\"') + '"'
}

function Get-McpServerJson {
    param([string]$LauncherPath)
    return [ordered]@{
        type    = "stdio"
        command = "powershell.exe"
        args    = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $LauncherPath)
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

function Install-GlobalMcpIfMissing {
    if ($Mode -ne "npx") {
        return
    }

    $mcpBin = Get-Command mcp-server-azuredevops -ErrorAction SilentlyContinue
    if ($mcpBin) {
        Write-Host "Global @azure-devops/mcp binary already available; skipping npm install."
        return
    }

    $npmCommandPath = Get-NpmCommandPath
    if ($npmCommandPath) {
        Write-Host "Installing @azure-devops/mcp globally..."
        & $npmCommandPath install -g "@azure-devops/mcp" --silent
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Global npm install failed (exit $LASTEXITCODE) - launcher will fall back to npx."
        }
    } else {
        Write-Warning "npm not found - skipping global install; launcher will use npx."
    }
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
            Write-Host "  Removed legacy standalone MCP server: $name"
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

# Writes or replaces a delimited block inside a markdown file.
# The block is wrapped in HTML comments so it survives manual edits above/below.
function Enable-PluginMcpJsonServer {
    param([string]$SettingsPath, [string]$ServerName)

    if (-not (Test-Path -LiteralPath $SettingsPath)) {
        return
    }

    try {
        $raw = Get-Content -LiteralPath $SettingsPath -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return
        }

        $json = $raw | ConvertFrom-Json
        $prop = $json.PSObject.Properties["disabledMcpjsonServers"]
        if ($null -eq $prop) {
            return
        }

        $filtered = @($prop.Value | Where-Object { $_ -ne $ServerName })
        if ($filtered.Count -eq @($prop.Value).Count) {
            return
        }

        if ($filtered.Count -eq 0) {
            $json.PSObject.Properties.Remove("disabledMcpjsonServers")
        } else {
            $prop.Value = $filtered
        }

        $json | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $SettingsPath -Encoding utf8
        Write-Host "  Enabled plugin .mcp.json server '$ServerName' in Claude settings: $SettingsPath"
    } catch {
        Write-Warning "Could not update $SettingsPath - remove disabledMcpjsonServers manually. $($_.Exception.Message)"
    }
}

function Merge-MarkdownBlock {
    param(
        [string]$Path,
        [string]$MarkerName,
        [string]$Content
    )

    $start = "<!-- $MarkerName`: start -->"
    $end   = "<!-- $MarkerName`: end -->"
    $block = "$start`n$Content`n$end"

    $dir = Split-Path -Parent $Path
    if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

    $existing = if (Test-Path -LiteralPath $Path) { Get-Content -LiteralPath $Path -Raw } else { "" }

    if ($existing -match [regex]::Escape($start)) {
        if (-not $Force) {
            Write-Host "  Already installed. Use -Force to update: $Path"
            return
        }
        $pattern = [regex]::Escape($start) + "[\s\S]*?" + [regex]::Escape($end)
        $updated = [regex]::Replace($existing, $pattern, $block)
        Set-Content -LiteralPath $Path -Value $updated -Encoding utf8 -NoNewline
    } else {
        $separator = if ($existing -and -not $existing.EndsWith("`n")) { "`n`n" } else { "`n" }
        Add-Content -LiteralPath $Path -Value "$separator$block" -Encoding utf8
    }
    Write-Host "  Context block written: $Path"
}

function Merge-VSCodeMcpServer {
    param([string]$Path, [string]$LauncherPath)

    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null

    if (Test-Path -LiteralPath $Path) {
        $raw  = Get-Content -LiteralPath $Path -Raw
        $json = if ([string]::IsNullOrWhiteSpace($raw)) { [pscustomobject]@{} } else { $raw | ConvertFrom-Json }
    } else {
        $json = [pscustomobject]@{}
    }

    if ($null -eq $json.PSObject.Properties["servers"]) {
        $json | Add-Member -NotePropertyName "servers" -NotePropertyValue ([pscustomobject]@{})
    }

    $servers = $json.servers
    if ($null -ne $servers.PSObject.Properties["azure-devops"] -and -not $Force) {
        Write-Host "  MCP entry already present. Use -Force to replace: $Path"
        return
    }

    if ($null -ne $servers.PSObject.Properties["azure-devops"]) {
        $servers.PSObject.Properties.Remove("azure-devops")
    }
    $servers | Add-Member -NotePropertyName "azure-devops" -NotePropertyValue (Get-McpServerJson -LauncherPath $LauncherPath)
    $json | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding utf8
    Write-Host "  Configured VS Code MCP: $Path"
}

# Adds a { "file": "<path>" } entry to github.copilot.chat.codeGeneration.instructions
# in the VS Code user settings.json. Idempotent - safe to run more than once.
function Merge-VSCodeCopilotInstructions {
    param([string]$SettingsPath, [string]$ContextFilePath)

    $parent = Split-Path -Parent $SettingsPath
    New-Item -ItemType Directory -Force -Path $parent | Out-Null

    if (Test-Path -LiteralPath $SettingsPath) {
        $raw  = Get-Content -LiteralPath $SettingsPath -Raw
        $json = if ([string]::IsNullOrWhiteSpace($raw)) { [pscustomobject]@{} } else { $raw | ConvertFrom-Json }
    } else {
        $json = [pscustomobject]@{}
    }

    $key = "github.copilot.chat.codeGeneration.instructions"
    $prop = $json.PSObject.Properties[$key]

    $instructions = if ($null -ne $prop) { @($prop.Value) } else { @() }
    $alreadyPresent = $instructions | Where-Object { $_.PSObject.Properties["file"] -and $_.file -eq $ContextFilePath }

    if ($null -ne $alreadyPresent -and -not $Force) {
        Write-Host "  Copilot instruction already present. Use -Force to update: $SettingsPath"
        return
    }

    $instructions = @($instructions | Where-Object { -not ($_.PSObject.Properties["file"] -and $_.file -eq $ContextFilePath) })
    $instructions += [pscustomobject]@{ file = $ContextFilePath }

    if ($null -ne $prop) {
        $prop.Value = $instructions
    } else {
        $json | Add-Member -NotePropertyName $key -NotePropertyValue $instructions
    }

    $json | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $SettingsPath -Encoding utf8
    Write-Host "  Added Copilot instruction reference: $SettingsPath"
}

function Remove-LegacyVSCodePromptFiles {
    param([string]$SettingsPath, [string]$PromptDirectory)

    if (Test-Path -LiteralPath $SettingsPath) {
        $raw = Get-Content -LiteralPath $SettingsPath -Raw
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $json = $raw | ConvertFrom-Json
            $key = "chat.promptFilesLocations"
            $prop = $json.PSObject.Properties[$key]
            $changed = $false
            if ($null -ne $prop -and $null -ne $prop.Value -and $prop.Value -is [pscustomobject]) {
                $locations = $prop.Value
                if ($null -ne $locations.PSObject.Properties[$PromptDirectory]) {
                    $locations.PSObject.Properties.Remove($PromptDirectory)
                    $changed = $true
                    Write-Host "  Removed legacy VS Code prompt location: $PromptDirectory"
                }
                if (@($locations.PSObject.Properties).Count -eq 0) {
                    $json.PSObject.Properties.Remove($key)
                    $changed = $true
                    Write-Host "  Removed empty VS Code prompt location setting"
                }
            }
            if ($changed) {
                $json | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $SettingsPath -Encoding utf8
            }
        }
    }

    if (Test-Path -LiteralPath $PromptDirectory) {
        Remove-Item -LiteralPath $PromptDirectory -Recurse -Force
        Write-Host "  Removed legacy VS Code prompts: $PromptDirectory"
    }
}

# -- Main -----------------------------------------------------------------------

$configureAll = $AllClients.IsPresent -or (-not $ConfigureCodex -and -not $ConfigureClaude -and -not $ConfigureVSCode)
$configureCodexNow = $configureAll -or $ConfigureCodex
$configureClaudeNow = $configureAll -or $ConfigureClaude
$configureVSCodeNow = $configureAll -or $ConfigureVSCode

$userHome      = if ([string]::IsNullOrWhiteSpace($env:ADO_MCP_HOME)) { $HOME } else { $env:ADO_MCP_HOME }
$adoHome       = Join-Path $userHome ".ado-mcp"
$launcherTarget = Join-Path $adoHome "ado-mcp.ps1"
$configTarget  = Join-Path $adoHome "config.json"
$copilotTarget = Join-Path $adoHome "copilot-context.md"
$repoRoot      = Split-Path -Parent $PSScriptRoot
$launcherSource = Join-Path $repoRoot "scripts\ado-mcp-launcher.ps1"

$sharedRupPlan = Read-TextFile -Path (Join-Path $repoRoot "shared\workflows\rup-planning.md")
$sharedMcpRules = Read-TextFile -Path (Join-Path $repoRoot "shared\mcp\azure-devops-tools.md")
$claudeContextBlock = Join-TextSections -Sections @(
    (Read-TextFile -Path (Join-Path $repoRoot "plugins\azure-devops-agents-claude\CLAUDE.md")),
    $sharedRupPlan,
    $sharedMcpRules
)
$codexContextBlock = Join-TextSections -Sections @(
    (Read-TextFile -Path (Join-Path $repoRoot "plugins\azure-devops-agents-codex\AGENTS.md")),
    $sharedRupPlan,
    $sharedMcpRules
)
$copilotContextFile = Join-TextSections -Sections @(
    (Read-TextFile -Path (Join-Path $repoRoot "plugins\azure-devops-agents-vscode\copilot-instructions.md")),
    $sharedRupPlan,
    $sharedMcpRules
)
# Infer mode from DockerImage if not explicitly set to docker
if ($Mode -ne "docker" -and -not [string]::IsNullOrWhiteSpace($DockerImage)) {
    $Mode = "docker"
}

if ($Mode -eq "docker") {
    Write-Warning "Docker mode is experimental and not recommended for general use. Use -Mode npx (the default) unless you have a specific reason."
    if ([string]::IsNullOrWhiteSpace($DockerImage)) {
        throw "-DockerImage is required when -Mode docker is set."
    }
} else {
    $DockerImage = ""
}

# Install launcher and config
New-Item -ItemType Directory -Force -Path $adoHome | Out-Null
Copy-Item -LiteralPath $launcherSource -Destination $launcherTarget -Force

$existingConfigForDefaults = Read-JsonFile -Path $configTarget
if ([string]::IsNullOrWhiteSpace($Project)) {
    $Project = Get-StringValue -Object $existingConfigForDefaults -Name "project"
}
if ([string]::IsNullOrWhiteSpace($Team)) {
    $Team = Get-StringValue -Object $existingConfigForDefaults -Name "team"
}
if ([string]::IsNullOrWhiteSpace($Project) -and $Host.Name -ne "Default Host") {
    $Project = Read-Host "Default Azure DevOps project (optional; repo .ado-mcp.json overrides)"
}
if (-not [string]::IsNullOrWhiteSpace($Project) -and [string]::IsNullOrWhiteSpace($Team) -and $Host.Name -ne "Default Host") {
    $Team = Read-Host "Default Azure DevOps team (optional; repo .ado-mcp.json overrides)"
}

if ((Test-Path -LiteralPath $configTarget) -and -not $Force) {
    $existingConfig  = Read-JsonFile -Path $configTarget
    $existingDocker  = Get-StringValue -Object $existingConfig -Name "dockerImage"
    $incomingDocker  = if ([string]::IsNullOrWhiteSpace($DockerImage)) { $null } else { $DockerImage }
    $dockerMismatch  = ($existingDocker -ne $incomingDocker)
    $orgMismatch     = (Get-StringValue -Object $existingConfig -Name "organization") -ne $Organization
    $projectMismatch = (Get-StringValue -Object $existingConfig -Name "project") -ne $(if ([string]::IsNullOrWhiteSpace($Project)) { $null } else { $Project })
    $teamMismatch    = (Get-StringValue -Object $existingConfig -Name "team") -ne $(if ([string]::IsNullOrWhiteSpace($Team)) { $null } else { $Team })

    if ($dockerMismatch -or $orgMismatch -or $projectMismatch -or $teamMismatch) {
        throw "Config already exists with different settings. Use -Force to overwrite: $configTarget"
    }
    Write-Host "MCP config already exists and matches - skipping (use -Force to replace): $configTarget"
} else {
    $configAuthentication = if ([string]::IsNullOrWhiteSpace($DockerImage)) { $Authentication } else { "envvar" }
    $config = [ordered]@{ organization = $Organization; authentication = $configAuthentication }
    if (-not [string]::IsNullOrWhiteSpace($Project)) { $config.project = $Project }
    if (-not [string]::IsNullOrWhiteSpace($Team)) { $config.team = $Team }
    if ($Domains.Count -gt 0) { $config.domains = $Domains }
    if (-not [string]::IsNullOrWhiteSpace($DockerImage)) { $config.dockerImage = $DockerImage }
    $config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $configTarget -Encoding utf8
    $modeLabel = if ([string]::IsNullOrWhiteSpace($DockerImage)) { "npx (local)" } else { "Docker ($DockerImage)" }
    Write-Host "Wrote MCP config [$modeLabel]: $configTarget"
}

Install-GlobalMcpIfMissing

if (-not [string]::IsNullOrWhiteSpace($DockerImage) -and -not [string]::IsNullOrWhiteSpace($AuthToken)) {
    [Environment]::SetEnvironmentVariable("ADO_MCP_AUTH_TOKEN", $AuthToken, "User")
    $env:ADO_MCP_AUTH_TOKEN = $AuthToken
    Write-Host "Stored ADO_MCP_AUTH_TOKEN as a user environment variable for Docker MCP mode."
}

# -- Codex ----------------------------------------------------------------------
if ($configureCodexNow) {
    Write-Host "Configuring Codex..."

    $codexDir  = Join-Path $userHome ".codex"
    $codexToml = Join-Path $codexDir "config.toml"
    New-Item -ItemType Directory -Force -Path $codexDir | Out-Null

    $tomlBlock = [string]::Join("`n", @(
        "",
        "[mcp_servers.azure-devops]",
        'command = "powershell.exe"',
        ('args = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", {0}]' -f (ConvertTo-TomlString -Value $launcherTarget))
    ))

    $existingToml = if (Test-Path -LiteralPath $codexToml) { Get-Content -LiteralPath $codexToml -Raw } else { "" }
    if ($existingToml -match '(?m)^\[mcp_servers\.azure-devops\]') {
        if (-not $Force) {
            Write-Host "  Codex MCP already configured. Use -Force to replace: $codexToml"
        } else {
            $pattern = '(?ms)^\[mcp_servers\.azure-devops\]\r?\n.*?(?=^\[|\z)'
            $replacement = $tomlBlock.Trim() + "`n"
            $updatedToml = [regex]::Replace($existingToml, $pattern, $replacement)
            Set-Content -LiteralPath $codexToml -Value $updatedToml -Encoding utf8 -NoNewline
            Write-Host "  Replaced Codex MCP: $codexToml"
        }
    } else {
        Add-Content -LiteralPath $codexToml -Value $tomlBlock -Encoding utf8
        Write-Host "  Configured Codex MCP: $codexToml"
    }

    # Global AGENTS.md - Codex reads this in every repo
    $codexAgentsPath = Join-Path $codexDir "AGENTS.md"
    Merge-MarkdownBlock -Path $codexAgentsPath -MarkerName "azure-devops-agents" -Content $codexContextBlock
}

# -- VS Code --------------------------------------------------------------------
if ($configureVSCodeNow) {
    Write-Host "Configuring VS Code..."

    $vsCodeMcpPath      = Join-Path $env:APPDATA "Code\User\mcp.json"
    $vsCodeSettingsPath = Join-Path $env:APPDATA "Code\User\settings.json"
    $legacyPromptDir    = Join-Path $adoHome "prompts"

    Set-Content -LiteralPath $copilotTarget -Value $copilotContextFile -Encoding utf8

    Merge-VSCodeMcpServer -Path $vsCodeMcpPath -LauncherPath $launcherTarget
    Merge-VSCodeCopilotInstructions -SettingsPath $vsCodeSettingsPath -ContextFilePath $copilotTarget
    Remove-LegacyVSCodePromptFiles -SettingsPath $vsCodeSettingsPath -PromptDirectory $legacyPromptDir
}

# -- Claude Code ----------------------------------------------------------------
$claudePluginInstalled = $false
if ($configureClaudeNow) {
    Write-Host "Configuring Claude Code..."

    $claude = Get-Command "claude" -ErrorAction SilentlyContinue
    if ($null -eq $claude) {
        Write-Host "  Claude CLI not found. Plugin was NOT registered. Run manually after installing Claude Code:"
        Write-Host "  claude plugin marketplace add --scope user `"$repoRoot`""
        Write-Host "  claude plugin install --scope user azure-devops-agents-claude@azure-devops-agents"
    } else {
        Remove-ClaudeUserMcpServer `
            -SuccessMessage "  Removed legacy standalone MCP server registrations." `
            -NotFoundMessage "  Legacy standalone MCP servers not registered, continuing." `
            -FailureMessage "Could not remove legacy standalone MCP server registrations."

        $marketplaceList = (& claude plugin marketplace list 2>&1) -join "`n"
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        if ($marketplaceList -match '(?m)^\s*>\s+azure-devops-agents\s*$') {
            Write-Host "  Claude marketplace already registered: azure-devops-agents"
        } else {
            & claude plugin marketplace add --scope user $repoRoot
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
            Write-Host "  Registered Claude marketplace: azure-devops-agents"
        }

        $pluginList = (& claude plugin list 2>&1) -join "`n"
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        if ($pluginList -match '(?m)^\s*>\s+azure-devops-agents-claude@azure-devops-agents\s*$') {
            Write-Host "  Claude plugin already installed: azure-devops-agents-claude"
            $claudePluginInstalled = $true
        } else {
            & claude plugin install --scope user azure-devops-agents-claude@azure-devops-agents
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
            $claudePluginInstalled = $true
        }
    }

    # Global CLAUDE.md - written regardless of whether claude CLI was found
    $claudeContextPath = Join-Path $userHome ".claude\CLAUDE.md"
    Merge-MarkdownBlock -Path $claudeContextPath -MarkerName "azure-devops-agents" -Content $claudeContextBlock

    $claudeSettingsPath = Join-Path $userHome ".claude\settings.json"
    Enable-PluginMcpJsonServer -SettingsPath $claudeSettingsPath -ServerName "azure-devops"
}

Write-Host ""
Write-Host "Done. Client summary:"
if ($configureClaudeNow) {
    if ($claudePluginInstalled) {
        Write-Host "  Claude Code : plugin installed + plugin MCP enabled + ~/.claude/CLAUDE.md updated"
    } else {
        Write-Host "  Claude Code : ~/.claude/CLAUDE.md updated (plugin install pending - run manual commands above)"
    }
}
if ($configureCodexNow) {
    Write-Host "  Codex       : MCP registered + ~/.codex/AGENTS.md updated"
}
if ($configureVSCodeNow) {
    Write-Host "  VS Code     : MCP registered + Copilot instruction added"
}
Write-Host ""
if (-not [string]::IsNullOrWhiteSpace($DockerImage)) {
    Write-Host "Docker auth      : set ADO_MCP_AUTH_TOKEN to your Azure DevOps PAT before starting any tool."
    Write-Host "                  Or rerun with -AuthToken <pat> to store it as a user environment variable."
} else {
    Write-Host "Auth defaults to azcli. Run 'az login' if needed."
    Write-Host "Service principal: set AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_TENANT_ID, then restart all tools."
}
Write-Host "Per-repo config  : add .ado-mcp.json -> { ""project"": ""YourProject"", ""team"": ""YourTeam"" }"
Write-Host "Project default  : stored in ~/.ado-mcp/config.json; repo .ado-mcp.json overrides it when present."
