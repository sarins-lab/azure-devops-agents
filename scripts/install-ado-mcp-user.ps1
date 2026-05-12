param(
    [Parameter(Mandatory = $true)]
    [string]$Organization,
    [ValidateSet("npx", "docker")]
    [string]$Mode = "npx",          # npx (default, recommended) or docker (experimental)
    [string]$Authentication = "azcli",
    [string[]]$Domains = @("core", "work", "work-items", "repositories", "wiki"),
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

# Writes or replaces a delimited block inside a markdown file.
# The block is wrapped in HTML comments so it survives manual edits above/below.
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

function Merge-VSCodePromptFileLocation {
    param([string]$SettingsPath, [string]$PromptDirectory)

    $parent = Split-Path -Parent $SettingsPath
    New-Item -ItemType Directory -Force -Path $parent | Out-Null

    if (Test-Path -LiteralPath $SettingsPath) {
        $raw  = Get-Content -LiteralPath $SettingsPath -Raw
        $json = if ([string]::IsNullOrWhiteSpace($raw)) { [pscustomobject]@{} } else { $raw | ConvertFrom-Json }
    } else {
        $json = [pscustomobject]@{}
    }

    $key = "chat.promptFilesLocations"
    $prop = $json.PSObject.Properties[$key]
    if ($null -eq $prop -or $null -eq $prop.Value -or -not ($prop.Value -is [pscustomobject])) {
        $locations = [pscustomobject]@{}
        if ($null -ne $prop) {
            $prop.Value = $locations
        } else {
            $json | Add-Member -NotePropertyName $key -NotePropertyValue $locations
        }
    } else {
        $locations = $prop.Value
    }

    if ($null -ne $locations.PSObject.Properties[$PromptDirectory]) {
        Write-Host "  VS Code prompt file location already present: $PromptDirectory"
    } else {
        $locations | Add-Member -NotePropertyName $PromptDirectory -NotePropertyValue $true
        Write-Host "  Added VS Code prompt file location: $PromptDirectory"
    }

    $json | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $SettingsPath -Encoding utf8
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
$promptDir     = Join-Path $adoHome "prompts"
$repoRoot      = Split-Path -Parent $PSScriptRoot
$launcherSource = Join-Path $repoRoot "scripts\ado-mcp-launcher.ps1"
$promptSourceDir = Join-Path $repoRoot "plugins\azure-devops-agents-vscode\prompts"

$sharedPlanStory = Read-TextFile -Path (Join-Path $repoRoot "shared\workflows\plan-story.md")
$sharedPlanFeature = Read-TextFile -Path (Join-Path $repoRoot "shared\workflows\plan-feature.md")
$sharedPlanEpic = Read-TextFile -Path (Join-Path $repoRoot "shared\workflows\plan-epic.md")
$sharedMcpRules = Read-TextFile -Path (Join-Path $repoRoot "shared\mcp\azure-devops-tools.md")
$claudeContextBlock = Join-TextSections -Sections @(
    (Read-TextFile -Path (Join-Path $repoRoot "plugins\azure-devops-agents-claude\CLAUDE.md")),
    $sharedMcpRules
)
$codexContextBlock = Join-TextSections -Sections @(
    (Read-TextFile -Path (Join-Path $repoRoot "plugins\azure-devops-agents-codex\AGENTS.md")),
    $sharedPlanStory,
    $sharedPlanFeature,
    $sharedPlanEpic,
    $sharedMcpRules
)
$copilotContextFile = Join-TextSections -Sections @(
    (Read-TextFile -Path (Join-Path $repoRoot "plugins\azure-devops-agents-vscode\copilot-instructions.md")),
    $sharedPlanStory,
    $sharedPlanFeature,
    $sharedPlanEpic,
    $sharedMcpRules
)
if ($configureVSCodeNow -and -not (Test-Path -LiteralPath $promptSourceDir)) {
    throw "Required VS Code prompt source directory not found: $promptSourceDir"
}

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

# Always install/update the MCP package globally so the launcher uses the direct
# binary rather than npx. npx has a cold-start delay that causes MCP clients to
# time out during the initialize handshake.
Write-Host "Installing @azure-devops/mcp globally..."
& npm install -g @azure-devops/mcp --silent

if ((Test-Path -LiteralPath $configTarget) -and -not $Force) {
    $existingConfig  = Read-JsonFile -Path $configTarget
    $existingDocker  = Get-StringValue -Object $existingConfig -Name "dockerImage"
    $incomingDocker  = if ([string]::IsNullOrWhiteSpace($DockerImage)) { $null } else { $DockerImage }
    $dockerMismatch  = ($existingDocker -ne $incomingDocker)
    $orgMismatch     = (Get-StringValue -Object $existingConfig -Name "organization") -ne $Organization

    if ($dockerMismatch -or $orgMismatch) {
        throw "Config already exists with different settings. Use -Force to overwrite: $configTarget"
    }
    Write-Host "MCP config already exists and matches - skipping (use -Force to replace): $configTarget"
} else {
    $configAuthentication = if ([string]::IsNullOrWhiteSpace($DockerImage)) { $Authentication } else { "envvar" }
    $config = [ordered]@{ organization = $Organization; authentication = $configAuthentication }
    if ($Domains.Count -gt 0) { $config.domains = $Domains }
    if (-not [string]::IsNullOrWhiteSpace($DockerImage)) { $config.dockerImage = $DockerImage }
    $config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $configTarget -Encoding utf8
    $mode = if ([string]::IsNullOrWhiteSpace($DockerImage)) { "npx (local)" } else { "Docker ($DockerImage)" }
    Write-Host "Wrote MCP config [$mode]: $configTarget"
}

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

    Set-Content -LiteralPath $copilotTarget -Value $copilotContextFile -Encoding utf8
    New-Item -ItemType Directory -Force -Path $promptDir | Out-Null
    Get-ChildItem -LiteralPath $promptSourceDir -Filter "*.prompt.md" | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $promptDir $_.Name) -Force
    }

    Merge-VSCodeMcpServer -Path $vsCodeMcpPath -LauncherPath $launcherTarget
    Merge-VSCodeCopilotInstructions -SettingsPath $vsCodeSettingsPath -ContextFilePath $copilotTarget
    Merge-VSCodePromptFileLocation -SettingsPath $vsCodeSettingsPath -PromptDirectory $promptDir
}

# -- Claude Code ----------------------------------------------------------------
$claudeMcpRegistered = $false
$claudePluginInstalled = $false
if ($configureClaudeNow) {
    Write-Host "Configuring Claude Code..."

    $claude = Get-Command "claude" -ErrorAction SilentlyContinue
    if ($null -eq $claude) {
        Write-Host "  Claude CLI not found. MCP and plugin were NOT registered. Run manually after installing Claude Code:"
        Write-Host "  claude mcp add --scope user azure-devops -- powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$launcherTarget`""
        Write-Host "  claude plugin marketplace add --scope user `"$repoRoot`""
        Write-Host "  claude plugin install --scope user azure-devops-agents-claude@azure-devops-agents"
    } else {
        & claude mcp add --scope user azure-devops -- powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcherTarget
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        $claudeMcpRegistered = $true

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
}

Write-Host ""
Write-Host "Done. Per-tool summary:"
if ($configureClaudeNow) {
    if ($claudeMcpRegistered) {
        if ($claudePluginInstalled) {
            Write-Host "  Claude Code : MCP registered + plugin installed + ~/.claude/CLAUDE.md updated"
        } else {
            Write-Host "  Claude Code : MCP registered + ~/.claude/CLAUDE.md updated"
        }
    } else {
        Write-Host "  Claude Code : ~/.claude/CLAUDE.md updated (MCP/plugin pending - run manual commands above)"
    }
}
if ($configureCodexNow) {
    Write-Host "  Codex       : MCP registered + ~/.codex/AGENTS.md updated"
}
if ($configureVSCodeNow) {
    Write-Host "  VS Code     : MCP registered + Copilot instruction + prompt files added"
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

