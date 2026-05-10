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

# ── Context blocks ─────────────────────────────────────────────────────────────
# Written into each tool's global context file so planning conventions apply
# in every repo, not just this one.

$claudeContextBlock = @'
## Azure DevOps — Sprint Planning (azure-devops-agents plugin)

The `azure-devops` MCP server is registered at user level. Place an `.ado-mcp.json`
file in any repo root to specify `project` and `team` — the launcher injects these
automatically. No manual project override is needed in tool calls.

### Work item hierarchy

```
Epic → Feature → User Story → Task
```

All items must be created with parent links. Never create a Feature without linking
it to its Epic, or a User Story without linking it to its Feature.

### Planning intent detection

Detect planning intent from natural language and route automatically — do not wait
for an explicit slash command:

| If user mentions | Use |
|------------------|-----|
| Epic, broad initiative, multiple features | `/plan-epic` |
| Feature, specific capability, named deliverable | `/plan-feature` |
| User story, "as a user", single behaviour | `/plan-story` |
| Ambiguous | Ask: "Are we planning an Epic, a Feature, or a User Story?" |

**Trigger on:** "we need to", "we should", "let's", "I want to", "plan", "design",
"build", "create", "define", "implement". Do **not** trigger for queries about
existing work ("what's in sprint 3?", "show me story #42").

### ADO field conventions

| Type | Required fields |
|------|----------------|
| Feature | Title, Description (SA technical approach), Tags |
| User Story | Title, Acceptance Criteria (Given/When/Then), Description (SA notes + Architect risks), Story Points, Iteration Path |
| Task | Title, Description, Remaining Work (hours), Assigned To |

### Traceability

After creating any work item, verify the parent link by reading it back with
`wit_work_item`. Fix missing links with `wit_work_item_link_write`. Never leave
a work item parentless.
'@

$codexContextBlock = @'
## Azure DevOps — Sprint Planning (azure-devops-agents plugin)

The `azure-devops` MCP server is configured at user level via `~/.codex/config.toml`.
Place `.ado-mcp.json` in any repo root to specify `project` and `team` — the launcher
injects these automatically.

### Work item hierarchy

```
Epic → Feature → User Story → Task
```

All items must be created with parent links.

### Planning agents

| Agent | Role |
|-------|------|
| `ba-agent` | User stories with Given/When/Then acceptance criteria |
| `sa-agent` | Technical design, dependency order, risk register |
| `architect-agent` | ADRs, cross-cutting concern audit, principle violations |
| `pm-agent` | Fibonacci estimates, story splitting, sprint assignment |

Run the full pipeline in order: BA → SA → Architect → PM.

### ADO field conventions

| Type | Required fields |
|------|----------------|
| Feature | Title, Description (SA technical approach), Tags (feature area) |
| User Story | Title, Acceptance Criteria (BA — Given/When/Then), Description (SA implementation notes + Architect concerns), Story Points, Iteration Path |
| Task | Title, Description, Remaining Work (hours), Assigned To |

### Traceability

After creating any work item, verify the parent link with `wit_work_item`. Fix
missing links with `wit_work_item_link_write`. Never leave a work item parentless.
'@

$copilotContextFile = @'
# Azure DevOps Sprint Planning

Use the `azure-devops` MCP server for all ADO operations. The launcher reads
`.ado-mcp.json` from the repo root to determine project and team automatically.

## Work item hierarchy

```
Epic → Feature → User Story → Task
```

Always create items with parent links. Never leave a work item parentless.

## Required fields

| Type | Required fields |
|------|----------------|
| Feature | Title, Description (SA technical approach), Tags |
| User Story | Title, Acceptance Criteria (Given/When/Then), Description (SA notes + Architect risks), Story Points, Iteration Path |
| Task | Title, Description, Remaining Work (hours), Assigned To |

## Traceability

After creating any work item, verify the parent link with `wit_work_item`.
Fix missing links with `wit_work_item_link_write`.
'@

# ── Helpers ────────────────────────────────────────────────────────────────────

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
# in the VS Code user settings.json. Idempotent — safe to run more than once.
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

# ── Main ───────────────────────────────────────────────────────────────────────

$configureAll = $AllClients.IsPresent -or (-not $ConfigureCodex -and -not $ConfigureClaude -and -not $ConfigureVSCode)

$userHome      = if ([string]::IsNullOrWhiteSpace($env:ADO_MCP_HOME)) { $HOME } else { $env:ADO_MCP_HOME }
$adoHome       = Join-Path $userHome ".ado-mcp"
$launcherTarget = Join-Path $adoHome "ado-mcp.ps1"
$configTarget  = Join-Path $adoHome "config.json"
$copilotTarget = Join-Path $adoHome "copilot-context.md"
$repoRoot      = Split-Path -Parent $PSScriptRoot
$launcherSource = Join-Path $repoRoot "scripts\ado-mcp-launcher.ps1"

# Install launcher and config
New-Item -ItemType Directory -Force -Path $adoHome | Out-Null
Copy-Item -LiteralPath $launcherSource -Destination $launcherTarget -Force

if ((Test-Path -LiteralPath $configTarget) -and -not $Force) {
    Write-Host "MCP config already exists (use -Force to replace): $configTarget"
} else {
    $config = [ordered]@{ organization = $Organization; authentication = $Authentication }
    if ($Domains.Count -gt 0) { $config.domains = $Domains }
    $config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $configTarget -Encoding utf8
    Write-Host "Wrote MCP config: $configTarget"
}

# Write Copilot context file (shared by VS Code; re-written on every install)
Set-Content -LiteralPath $copilotTarget -Value $copilotContextFile -Encoding utf8

# ── Codex ──────────────────────────────────────────────────────────────────────
if ($configureAll -or $ConfigureCodex) {
    Write-Host "Configuring Codex..."

    $codexDir  = Join-Path $userHome ".codex"
    $codexToml = Join-Path $codexDir "config.toml"
    New-Item -ItemType Directory -Force -Path $codexDir | Out-Null

    $tomlBlock = @"

[mcp_servers.azure-devops]
command = "powershell.exe"
args = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $(ConvertTo-TomlString -Value $launcherTarget)]
"@

    $existingToml = if (Test-Path -LiteralPath $codexToml) { Get-Content -LiteralPath $codexToml -Raw } else { "" }
    if ($existingToml -match '(?m)^\[mcp_servers\.azure-devops\]') {
        if (-not $Force) {
            Write-Host "  Codex MCP already configured. Use -Force to replace manually: $codexToml"
        } else {
            throw "Codex TOML replacement is not automated. Edit $codexToml manually and re-run."
        }
    } else {
        Add-Content -LiteralPath $codexToml -Value $tomlBlock -Encoding utf8
        Write-Host "  Configured Codex MCP: $codexToml"
    }

    # Global AGENTS.md — Codex reads this in every repo
    $codexAgentsPath = Join-Path $codexDir "AGENTS.md"
    Merge-MarkdownBlock -Path $codexAgentsPath -MarkerName "azure-devops-agents" -Content $codexContextBlock
}

# ── VS Code ────────────────────────────────────────────────────────────────────
if ($configureAll -or $ConfigureVSCode) {
    Write-Host "Configuring VS Code..."

    $vsCodeMcpPath      = Join-Path $env:APPDATA "Code\User\mcp.json"
    $vsCodeSettingsPath = Join-Path $env:APPDATA "Code\User\settings.json"

    Merge-VSCodeMcpServer -Path $vsCodeMcpPath -LauncherPath $launcherTarget
    Merge-VSCodeCopilotInstructions -SettingsPath $vsCodeSettingsPath -ContextFilePath $copilotTarget
}

# ── Claude Code ────────────────────────────────────────────────────────────────
if ($configureAll -or $ConfigureClaude) {
    Write-Host "Configuring Claude Code..."

    $claude = Get-Command "claude" -ErrorAction SilentlyContinue
    if ($null -eq $claude) {
        Write-Host "  Claude CLI not found. Run this after installing Claude Code:"
        Write-Host "  claude mcp add --scope user azure-devops -- powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$launcherTarget`""
    } else {
        & claude mcp add --scope user azure-devops -- powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcherTarget
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }

    # Global CLAUDE.md — Claude Code reads this in every project
    $claudeContextPath = Join-Path $userHome ".claude\CLAUDE.md"
    Merge-MarkdownBlock -Path $claudeContextPath -MarkerName "azure-devops-agents" -Content $claudeContextBlock
}

Write-Host ""
Write-Host "Done. Per-tool summary:"
Write-Host "  Claude Code : MCP registered + ~/.claude/CLAUDE.md updated"
Write-Host "  Codex       : MCP registered + ~/.codex/AGENTS.md updated"
Write-Host "  VS Code     : MCP registered + Copilot instruction added (references $copilotTarget)"
Write-Host ""
Write-Host "Auth defaults to azcli. Run 'az login' if needed."
Write-Host "Service principal: set AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_TENANT_ID, then restart all tools."
Write-Host "Per-repo config  : add .ado-mcp.json -> { ""project"": ""YourProject"", ""team"": ""YourTeam"" }"
