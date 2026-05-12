param(
    [string]$Organization = $env:ADO_MCP_ORG,
    [ValidateSet("All", "Claude", "Codex", "VSCode")]
    [string[]]$Clients = @("All"),
    [string]$Authentication = "azcli",
    [string[]]$Domains = @("core", "work", "work-items", "repositories", "wiki"),
    [string]$DockerImage = "",
    [string]$AuthToken = "",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Test-WindowsPlatform {
    if ($PSVersionTable.PSEdition -eq "Desktop") {
        return $true
    }

    $isWindowsVariable = Get-Variable -Name IsWindows -ErrorAction SilentlyContinue
    if ($null -ne $isWindowsVariable) {
        return [bool]$isWindowsVariable.Value
    }

    return $env:OS -eq "Windows_NT"
}

function Remove-JsonCommentsAndTrailingCommas {
    param([string]$Content)

    $withoutComments = [System.Text.StringBuilder]::new()
    $inString = $false
    $escaped = $false
    $inLineComment = $false
    $inBlockComment = $false

    for ($i = 0; $i -lt $Content.Length; $i++) {
        $ch = $Content[$i]
        $next = if ($i + 1 -lt $Content.Length) { $Content[$i + 1] } else { [char]0 }

        if ($inLineComment) {
            if ($ch -eq "`r" -or $ch -eq "`n") {
                $inLineComment = $false
                [void]$withoutComments.Append($ch)
            }
            continue
        }

        if ($inBlockComment) {
            if ($ch -eq "*" -and $next -eq "/") {
                $inBlockComment = $false
                $i++
            }
            continue
        }

        if ($inString) {
            [void]$withoutComments.Append($ch)
            if ($escaped) {
                $escaped = $false
            } elseif ($ch -eq "\") {
                $escaped = $true
            } elseif ($ch -eq '"') {
                $inString = $false
            }
            continue
        }

        if ($ch -eq '"') {
            $inString = $true
            [void]$withoutComments.Append($ch)
            continue
        }

        if ($ch -eq "/" -and $next -eq "/") {
            $inLineComment = $true
            $i++
            continue
        }

        if ($ch -eq "/" -and $next -eq "*") {
            $inBlockComment = $true
            $i++
            continue
        }

        [void]$withoutComments.Append($ch)
    }

    $cleaned = $withoutComments.ToString()
    $withoutTrailingCommas = [System.Text.StringBuilder]::new()
    $inString = $false
    $escaped = $false

    for ($i = 0; $i -lt $cleaned.Length; $i++) {
        $ch = $cleaned[$i]

        if ($inString) {
            [void]$withoutTrailingCommas.Append($ch)
            if ($escaped) {
                $escaped = $false
            } elseif ($ch -eq "\") {
                $escaped = $true
            } elseif ($ch -eq '"') {
                $inString = $false
            }
            continue
        }

        if ($ch -eq '"') {
            $inString = $true
            [void]$withoutTrailingCommas.Append($ch)
            continue
        }

        if ($ch -eq ",") {
            $j = $i + 1
            while ($j -lt $cleaned.Length -and [char]::IsWhiteSpace($cleaned[$j])) {
                $j++
            }

            if ($j -lt $cleaned.Length -and ($cleaned[$j] -eq "}" -or $cleaned[$j] -eq "]")) {
                continue
            }
        }

        [void]$withoutTrailingCommas.Append($ch)
    }

    return $withoutTrailingCommas.ToString()
}

function ConvertFrom-JsonOrJsonC {
    param(
        [string]$Content,
        [string]$Path
    )

    try {
        return $Content | ConvertFrom-Json
    } catch {
        try {
            return (Remove-JsonCommentsAndTrailingCommas -Content $Content) | ConvertFrom-Json
        } catch {
            throw "Unable to parse JSON/JSONC file '$Path'. Remove invalid comments or trailing commas, then rerun the installer. $($_.Exception.Message)"
        }
    }
}

function Write-Utf8NoBomFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowNull()][string]$Value,
        [switch]$NoNewline
    )

    $parent = Split-Path -Parent $Path
    if ($parent) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    $text = if ($null -eq $Value) { "" } else { $Value }
    if (-not $NoNewline -and -not $text.EndsWith("`n")) {
        $text += "`n"
    }

    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $text, $encoding)
}

function Add-Utf8NoBomFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowNull()][string]$Value
    )

    $parent = Split-Path -Parent $Path
    if ($parent) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::AppendAllText($Path, [string]$Value, $encoding)
}

function Set-CurrentAndPersistentUserEnvironmentVariable {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Value
    )

    Set-Item -Path "Env:$Name" -Value $Value
    if ($script:IsWindowsPlatform) {
        [Environment]::SetEnvironmentVariable($Name, $Value, "User")
    }
}

if (-not $PSBoundParameters.ContainsKey("Clients") -and -not [string]::IsNullOrWhiteSpace($env:ADO_MCP_CLIENTS)) {
    $Clients = @($env:ADO_MCP_CLIENTS -split "," | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

$validClients = @("All", "Claude", "Codex", "VSCode")
foreach ($client in $Clients) {
    if ($validClients -notcontains $client) {
        throw "Unknown client '$client'. Valid clients: $($validClients -join ', ')."
    }
}

if (-not $PSBoundParameters.ContainsKey("Authentication") -and -not [string]::IsNullOrWhiteSpace($env:ADO_MCP_AUTHENTICATION)) {
    $Authentication = $env:ADO_MCP_AUTHENTICATION
}

if (-not $PSBoundParameters.ContainsKey("Domains") -and -not [string]::IsNullOrWhiteSpace($env:ADO_MCP_DOMAINS)) {
    $Domains = @($env:ADO_MCP_DOMAINS -split "," | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

if (-not $PSBoundParameters.ContainsKey("DockerImage") -and -not [string]::IsNullOrWhiteSpace($env:ADO_MCP_DOCKER_IMAGE)) {
    $DockerImage = $env:ADO_MCP_DOCKER_IMAGE
}

if (-not $PSBoundParameters.ContainsKey("AuthToken") -and -not [string]::IsNullOrWhiteSpace($env:ADO_MCP_AUTH_TOKEN)) {
    $AuthToken = $env:ADO_MCP_AUTH_TOKEN
}

if (-not $PSBoundParameters.ContainsKey("Force") -and $env:ADO_MCP_FORCE -match "^(1|true|TRUE|yes|YES)$") {
    $Force = $true
}

$script:IsWindowsPlatform = Test-WindowsPlatform
if (-not $script:IsWindowsPlatform) {
    throw "scripts/install-online.ps1 is supported on Windows only. On macOS/Linux, use: curl -fsSL https://raw.githubusercontent.com/sarins-lab/azure-devops-agents/main/scripts/install-online.sh | bash"
}
$script:McpPowerShellCommand = "powershell.exe"

if ([string]::IsNullOrWhiteSpace($Organization)) {
    throw "Azure DevOps organization is required. Pass -Organization <org> or set ADO_MCP_ORG before running this script."
}

$LauncherScript = @'
$ErrorActionPreference = "Stop"

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $content = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($content)) {
        return $null
    }

    return $content | ConvertFrom-Json
}

function Find-RepoConfig {
    if (-not [string]::IsNullOrWhiteSpace($env:ADO_MCP_REPO_CONFIG)) {
        if (Test-Path -LiteralPath $env:ADO_MCP_REPO_CONFIG) {
            return (Resolve-Path -LiteralPath $env:ADO_MCP_REPO_CONFIG).Path
        }
    }

    $current = (Get-Location).Path
    while (-not [string]::IsNullOrWhiteSpace($current)) {
        $candidate = Join-Path $current ".ado-mcp.json"
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }

        $parent = Split-Path -Parent $current
        if ($parent -eq $current) {
            break
        }

        $current = $parent
    }

    return $null
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

$userHome = if ([string]::IsNullOrWhiteSpace($env:ADO_MCP_HOME)) { $HOME } else { $env:ADO_MCP_HOME }
$userConfigPath = Join-Path $userHome ".ado-mcp\config.json"
$userConfig = Read-JsonFile -Path $userConfigPath
$repoConfigPath = Find-RepoConfig
$repoConfig = if ($repoConfigPath) { Read-JsonFile -Path $repoConfigPath } else { $null }

$organization = Get-StringValue -Object $userConfig -Name "organization"
if ([string]::IsNullOrWhiteSpace($organization)) {
    $organization = $env:ADO_MCP_ORG
}

if ([string]::IsNullOrWhiteSpace($organization)) {
    throw "Azure DevOps organization is not configured. Set ADO_MCP_ORG or create $userConfigPath."
}

$authentication = Get-StringValue -Object $userConfig -Name "authentication"
if ([string]::IsNullOrWhiteSpace($authentication)) {
    $authentication = "azcli"
}

$dockerImage = Get-StringValue -Object $userConfig -Name "dockerImage"

$project = Get-StringValue -Object $repoConfig -Name "project"
if (-not [string]::IsNullOrWhiteSpace($project)) {
    $env:ado_mcp_project = $project
}

$team = Get-StringValue -Object $repoConfig -Name "team"
if (-not [string]::IsNullOrWhiteSpace($team)) {
    $env:ado_mcp_team = $team
}

$domains = @()
if ($null -ne $userConfig -and $null -ne $userConfig.PSObject.Properties["domains"]) {
    $domains = @($userConfig.domains) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
}
if ($null -ne $repoConfig -and $null -ne $repoConfig.PSObject.Properties["domains"]) {
    $domains = @($repoConfig.domains) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
}

if (-not [string]::IsNullOrWhiteSpace($dockerImage)) {
    if ([string]::IsNullOrWhiteSpace($env:ADO_MCP_AUTH_TOKEN)) {
        throw "Docker MCP mode requires ADO_MCP_AUTH_TOKEN in the host environment. Set it to an Azure DevOps PAT before starting the IDE."
    }

    $dockerArgs = @(
        "run", "-i", "--rm",
        "-e", "ADO_ORG=$organization",
        "-e", "ADO_MCP_AUTH_TOKEN"
    )
    if (-not [string]::IsNullOrWhiteSpace($project)) {
        $dockerArgs += "-e"
        $dockerArgs += "ado_mcp_project=$project"
    }
    if (-not [string]::IsNullOrWhiteSpace($team)) {
        $dockerArgs += "-e"
        $dockerArgs += "ado_mcp_team=$team"
    }
    if ($domains.Count -gt 0) {
        $dockerArgs += "-e"
        $dockerArgs += "ADO_DOMAINS=$($domains -join ',')"
    }
    $dockerArgs += $dockerImage

    & docker @dockerArgs
    exit $LASTEXITCODE
}

if ($authentication -eq "azcli") {
    $hasServicePrincipalEnv =
        -not [string]::IsNullOrWhiteSpace($env:AZURE_CLIENT_ID) -and
        -not [string]::IsNullOrWhiteSpace($env:AZURE_CLIENT_SECRET) -and
        -not [string]::IsNullOrWhiteSpace($env:AZURE_TENANT_ID)

    $shouldLogin = $false
    if ($hasServicePrincipalEnv) {
        $currentAzUser = & az account show --query user.name -o tsv --only-show-errors 2>$null
        if ($LASTEXITCODE -ne 0 -or $currentAzUser -ne $env:AZURE_CLIENT_ID) {
            $shouldLogin = $true
        }
    } else {
        & az account show --only-show-errors 1>$null 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "Azure CLI is not logged in, and AZURE_CLIENT_ID/AZURE_CLIENT_SECRET/AZURE_TENANT_ID are not all set."
        }
    }

    if ($shouldLogin) {
        & az login `
            --service-principal `
            --username $env:AZURE_CLIENT_ID `
            --password $env:AZURE_CLIENT_SECRET `
            --tenant $env:AZURE_TENANT_ID `
            --only-show-errors 1>$null

        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }
    }
}

$npxArgs = @("-y", "@azure-devops/mcp", $organization, "--authentication", $authentication)
foreach ($domain in $domains) {
    $npxArgs += "-d"
    $npxArgs += [string]$domain
}

& npx @npxArgs
exit $LASTEXITCODE
'@

$McpRules = @'
# Azure DevOps MCP Tooling

Use Microsoft's official `@azure-devops/mcp` package through the `azure-devops` MCP server.

Tool names use the `mcp_ado_*` naming pattern.

`mcp_ado_wit_add_child_work_items` creates child work items and parent links. It supports title, description, area path, iteration path, and Markdown/HTML format.

It does not set fields such as Acceptance Criteria, Story Points, or Tags. Add those afterward with `mcp_ado_wit_update_work_item`.

Use `mcp_ado_wit_work_items_link` only to repair or add links after creation.

For backlog lookup, call `mcp_ado_wit_list_backlogs` first, then call `mcp_ado_wit_list_backlog_work_items` with `project`, `team`, and `backlogId`.

For wiki lookup, use `mcp_ado_wiki_list_wikis`, `mcp_ado_wiki_list_pages`, `mcp_ado_wiki_get_page`, and `mcp_ado_wiki_get_page_content`.
'@

$PlanStory = @'
# plan-story

Create one Azure DevOps User Story under an existing Feature.

1. Load context. If the prompt contains `under feature <id>`, call `mcp_ado_wit_get_work_item` for that Feature. If no Feature ID is specified, ask for the ADO Feature ID before creating anything.
2. BA phase. Draft one story in `As a [persona] I want [goal] so that [value]` format with 2-4 Given/When/Then acceptance criteria and an explicit out-of-scope boundary. Pause for confirmation.
3. SA phase. Add one implementation note covering what changes, which service owns it, how it integrates, and the key technical decision. Pause for confirmation.
4. PM phase. Estimate Fibonacci story points, recommend a sprint using `mcp_ado_work_list_team_iterations` and `mcp_ado_work_get_team_capacity`, and flag if the story should be split. Pause before creating anything in ADO.
5. Create after confirmation with `mcp_ado_wit_add_child_work_items` under the Feature, then use `mcp_ado_wit_update_work_item` for Acceptance Criteria and Story Points.
6. Read back with `mcp_ado_wit_get_work_item`. If the parent link is missing, call `mcp_ado_wit_work_items_link`.
'@

$PlanFeature = @'
# plan-feature

Run the BA, SA, Architect, and PM planning flow for one Feature, then create linked Azure DevOps work items.

1. Load context. If a Feature ID is provided, call `mcp_ado_wit_get_work_item` for the Feature and parent Epic. If only a description is provided, ask for the parent Epic ID before creating anything.
2. BA phase. Decompose the Feature into 2-6 User Stories with Given/When/Then acceptance criteria and explicit out-of-scope boundaries. Pause for confirmation.
3. SA phase. Produce a feature-level technical design and per-story implementation notes. Ground the design with official repo tools. Pause for confirmation.
4. Architect phase. Read prior ADR context with wiki tools. Write ADRs for significant decisions and audit cross-cutting concerns. Pause for confirmation.
5. PM phase. Estimate story points, order by dependency and value, and assign stories to sprints using team iteration and capacity tools. Pause before creating anything in ADO.
6. Create parent-before-child with `mcp_ado_wit_add_child_work_items`; enrich fields with `mcp_ado_wit_update_work_item`; verify every link.
'@

$PlanEpic = @'
# plan-epic

Run the full BA, SA, Architect, and PM planning flow for an Epic, then create linked Azure DevOps Features, User Stories, and ADR pages.

1. Load context. If an Epic ID is provided, call `mcp_ado_wit_get_work_item` for the Epic. If only a description is provided, ask whether to create a new Epic or plan against an existing Epic.
2. BA phase. Decompose the Epic into Features and User Stories with Given/When/Then acceptance criteria. Pause for confirmation.
3. SA phase. Add technical design to each Feature and implementation notes to each Story. Ground the design in repositories using official repo tools. Pause for confirmation.
4. Architect phase. Read existing ADRs with the wiki tool sequence. Write new ADRs and cross-cutting concern findings. Pause for confirmation.
5. PM phase. Estimate story points, order by dependency and value, and assign stories to sprints. Pause before creating anything in ADO.
6. Create items parent-before-child, then verify traceability with `mcp_ado_wit_get_work_item`.
'@

$CodexContext = @'
# Azure DevOps - Sprint Planning (azure-devops-agents)

The `azure-devops` MCP server is configured at user level via `~/.codex/config.toml`.
Place `.ado-mcp.json` in any repo root to specify `project` and `team`; the launcher injects them automatically.

Epic -> Feature -> User Story -> Task

All items must be created with parent links. Never leave a work item parentless.

Run the planning workflow automatically when planning intent is detected. Also recognize `/plan-story`, `/plan-feature`, and `/plan-epic` as routing instructions. Do not create Azure DevOps work items until the user confirms the plan.
'@

$ClaudeContext = @'
# Azure DevOps - Sprint Planning (azure-devops-agents)

Use the `azure-devops` MCP server for Azure DevOps planning work. Place `.ado-mcp.json` in any repo root to specify `project` and `team`; the launcher injects them automatically.

Epic -> Feature -> User Story -> Task

Pause for user confirmation after each planning phase. Never create Azure DevOps work items until the user confirms the plan.
'@

$CopilotContext = @'
# Azure DevOps Sprint Planning

Use the `azure-devops` MCP server for all Azure DevOps operations. The launcher reads `.ado-mcp.json` from the repo root to determine project and team automatically.

Epic -> Feature -> User Story -> Task

Always create items with parent links. Never leave a work item parentless. Recognize `/plan-epic`, `/plan-feature`, `/plan-story`, and natural planning intent.
'@

$PromptPlanStory = @'
---
name: plan-story
description: Create one Azure DevOps user story with acceptance criteria, implementation notes, estimate, sprint recommendation, and parent traceability.
argument-hint: <story-description> [under feature <feature-id>]
tools: ["azure-devops/*"]
---

Create a single well-formed Azure DevOps User Story under the specified Feature. Follow the embedded plan-story workflow from the Azure DevOps Sprint Planning context. Do not create anything until the user confirms.
'@

$PromptPlanFeature = @'
---
name: plan-feature
description: Plan one Azure DevOps feature with stories, implementation notes, ADR guidance, estimate, sprint assignment, and traceability.
argument-hint: <feature-id or feature-description> [under epic <epic-id>]
tools: ["azure-devops/*"]
---

Plan a feature using BA, SA, Architect, and PM phases. Follow the embedded plan-feature workflow from the Azure DevOps Sprint Planning context. Do not create anything until the user confirms.
'@

$PromptPlanEpic = @'
---
name: plan-epic
description: Plan one Azure DevOps epic with features, stories, ADR guidance, estimates, sprint assignment, and traceability.
argument-hint: <epic-id or epic-description>
tools: ["azure-devops/*"]
---

Plan an epic using BA, SA, Architect, and PM phases. Follow the embedded plan-epic workflow from the Azure DevOps Sprint Planning context. Do not create anything until the user confirms.
'@

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

function ConvertTo-TomlString {
    param([string]$Value)
    return '"' + $Value.Replace('\', '\\').Replace('"', '\"') + '"'
}

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $content = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($content)) {
        return $null
    }

    return ConvertFrom-JsonOrJsonC -Content $content -Path $Path
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

function Get-McpServerJson {
    param([string]$LauncherPath)
    return [ordered]@{
        type = "stdio"
        command = $script:McpPowerShellCommand
        args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $LauncherPath)
    }
}

function Merge-MarkdownBlock {
    param(
        [string]$Path,
        [string]$MarkerName,
        [string]$Content
    )

    $start = "<!-- $MarkerName`: start -->"
    $end = "<!-- $MarkerName`: end -->"
    $block = "$start`n$Content`n$end"

    $dir = Split-Path -Parent $Path
    if ($dir) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }

    $existing = if (Test-Path -LiteralPath $Path) { Get-Content -LiteralPath $Path -Raw } else { "" }
    if ($existing -match [regex]::Escape($start)) {
        if (-not $Force) {
            Write-Host "  Already installed. Use -Force to update: $Path"
            return
        }
        $pattern = [regex]::Escape($start) + "[\s\S]*?" + [regex]::Escape($end)
        $updated = [regex]::Replace($existing, $pattern, $block)
        Write-Utf8NoBomFile -Path $Path -Value $updated -NoNewline
    } else {
        $separator = if ($existing -and -not $existing.EndsWith("`n")) { "`n`n" } else { "`n" }
        Add-Utf8NoBomFile -Path $Path -Value "$separator$block`n"
    }
    Write-Host "  Context block written: $Path"
}

function Merge-VSCodeMcpServer {
    param([string]$Path, [string]$LauncherPath)

    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null

    if (Test-Path -LiteralPath $Path) {
        $json = Read-JsonFile -Path $Path
        if ($null -eq $json) {
            $json = [pscustomobject]@{}
        }
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
    Write-Utf8NoBomFile -Path $Path -Value (($json | ConvertTo-Json -Depth 12) + "`n") -NoNewline
    Write-Host "  Configured VS Code MCP: $Path"
}

function Merge-VSCodeCopilotInstructions {
    param([string]$SettingsPath, [string]$ContextFilePath)

    $parent = Split-Path -Parent $SettingsPath
    New-Item -ItemType Directory -Force -Path $parent | Out-Null

    if (Test-Path -LiteralPath $SettingsPath) {
        $json = Read-JsonFile -Path $SettingsPath
        if ($null -eq $json) {
            $json = [pscustomobject]@{}
        }
    } else {
        $json = [pscustomobject]@{}
    }

    $key = "github.copilot.chat.codeGeneration.instructions"
    $prop = $json.PSObject.Properties[$key]
    $instructions = if ($null -ne $prop) { @($prop.Value) } else { @() }
    $instructions = @($instructions | Where-Object { -not ($_.PSObject.Properties["file"] -and $_.file -eq $ContextFilePath) })
    $instructions += [pscustomobject]@{ file = $ContextFilePath }

    if ($null -ne $prop) {
        $prop.Value = $instructions
    } else {
        $json | Add-Member -NotePropertyName $key -NotePropertyValue $instructions
    }

    Write-Utf8NoBomFile -Path $SettingsPath -Value (($json | ConvertTo-Json -Depth 12) + "`n") -NoNewline
    Write-Host "  Added Copilot instruction reference: $SettingsPath"
}

function Merge-VSCodePromptFileLocation {
    param([string]$SettingsPath, [string]$PromptDirectory)

    $parent = Split-Path -Parent $SettingsPath
    New-Item -ItemType Directory -Force -Path $parent | Out-Null

    if (Test-Path -LiteralPath $SettingsPath) {
        $json = Read-JsonFile -Path $SettingsPath
        if ($null -eq $json) {
            $json = [pscustomobject]@{}
        }
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

    if ($null -eq $locations.PSObject.Properties[$PromptDirectory]) {
        $locations | Add-Member -NotePropertyName $PromptDirectory -NotePropertyValue $true
    }

    Write-Utf8NoBomFile -Path $SettingsPath -Value (($json | ConvertTo-Json -Depth 12) + "`n") -NoNewline
    Write-Host "  Added VS Code prompt file location: $PromptDirectory"
}

$configureAll = $Clients -contains "All"
$configureCodexNow = $configureAll -or ($Clients -contains "Codex")
$configureClaudeNow = $configureAll -or ($Clients -contains "Claude")
$configureVSCodeNow = $configureAll -or ($Clients -contains "VSCode")

$userHome = if ([string]::IsNullOrWhiteSpace($env:ADO_MCP_HOME)) { $HOME } else { $env:ADO_MCP_HOME }
$adoHome = Join-Path $userHome ".ado-mcp"
$launcherTarget = Join-Path $adoHome "ado-mcp.ps1"
$configTarget = Join-Path $adoHome "config.json"
$copilotTarget = Join-Path $adoHome "copilot-context.md"
$promptDir = Join-Path $adoHome "prompts"

$codexContextBlock = Join-TextSections -Sections @($CodexContext, $PlanStory, $PlanFeature, $PlanEpic, $McpRules)
$claudeContextBlock = Join-TextSections -Sections @($ClaudeContext, $McpRules)
$copilotContextFile = Join-TextSections -Sections @($CopilotContext, $PlanStory, $PlanFeature, $PlanEpic, $McpRules)

New-Item -ItemType Directory -Force -Path $adoHome | Out-Null
Write-Utf8NoBomFile -Path $launcherTarget -Value ($LauncherScript.TrimEnd() + "`n") -NoNewline
Write-Host "Wrote online MCP launcher: $launcherTarget"

if ((Test-Path -LiteralPath $configTarget) -and -not $Force) {
    $existingConfig = Read-JsonFile -Path $configTarget
    $existingDocker = Get-StringValue -Object $existingConfig -Name "dockerImage"
    $incomingDocker = if ([string]::IsNullOrWhiteSpace($DockerImage)) { $null } else { $DockerImage }
    $dockerMismatch = ($existingDocker -ne $incomingDocker)
    $orgMismatch = (Get-StringValue -Object $existingConfig -Name "organization") -ne $Organization

    if ($dockerMismatch -or $orgMismatch) {
        throw "Config already exists with different settings. Use -Force to overwrite: $configTarget"
    }
    Write-Host "MCP config already exists and matches - skipping: $configTarget"
} else {
    $configAuthentication = if ([string]::IsNullOrWhiteSpace($DockerImage)) { $Authentication } else { "envvar" }
    $config = [ordered]@{ organization = $Organization; authentication = $configAuthentication }
    if ($Domains.Count -gt 0) {
        $config.domains = $Domains
    }
    if (-not [string]::IsNullOrWhiteSpace($DockerImage)) {
        $config.dockerImage = $DockerImage
    }
    Write-Utf8NoBomFile -Path $configTarget -Value (($config | ConvertTo-Json -Depth 8) + "`n") -NoNewline
    $mode = if ([string]::IsNullOrWhiteSpace($DockerImage)) { "npx (local)" } else { "Docker ($DockerImage)" }
    Write-Host "Wrote MCP config [$mode]: $configTarget"
}

if (-not [string]::IsNullOrWhiteSpace($DockerImage) -and -not [string]::IsNullOrWhiteSpace($AuthToken)) {
    Set-CurrentAndPersistentUserEnvironmentVariable -Name "ADO_MCP_AUTH_TOKEN" -Value $AuthToken
    Write-Host "Stored ADO_MCP_AUTH_TOKEN as a user environment variable for Docker MCP mode."
}

if ($configureCodexNow) {
    Write-Host "Configuring Codex..."

    $codexDir = Join-Path $userHome ".codex"
    $codexToml = Join-Path $codexDir "config.toml"
    New-Item -ItemType Directory -Force -Path $codexDir | Out-Null

    $tomlBlock = [string]::Join("`n", @(
        "",
        "[mcp_servers.azure-devops]",
        "command = $(ConvertTo-TomlString -Value $script:McpPowerShellCommand)",
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
            Write-Utf8NoBomFile -Path $codexToml -Value $updatedToml -NoNewline
            Write-Host "  Replaced Codex MCP: $codexToml"
        }
    } else {
        Add-Utf8NoBomFile -Path $codexToml -Value "$tomlBlock`n"
        Write-Host "  Configured Codex MCP: $codexToml"
    }

    Merge-MarkdownBlock -Path (Join-Path $codexDir "AGENTS.md") -MarkerName "azure-devops-agents" -Content $codexContextBlock
}

if ($configureVSCodeNow) {
    if ([string]::IsNullOrWhiteSpace($env:APPDATA)) {
        throw "APPDATA is not set; cannot locate VS Code user settings on Windows. On macOS/Linux, use scripts/install-online.sh."
    }

    Write-Host "Configuring VS Code..."

    $vsCodeUserDir = Join-Path $env:APPDATA "Code\User"
    $vsCodeMcpPath = Join-Path $vsCodeUserDir "mcp.json"
    $vsCodeSettingsPath = Join-Path $vsCodeUserDir "settings.json"

    Write-Utf8NoBomFile -Path $copilotTarget -Value ($copilotContextFile.TrimEnd() + "`n") -NoNewline
    New-Item -ItemType Directory -Force -Path $promptDir | Out-Null
    Write-Utf8NoBomFile -Path (Join-Path $promptDir "plan-story.prompt.md") -Value ($PromptPlanStory.TrimEnd() + "`n") -NoNewline
    Write-Utf8NoBomFile -Path (Join-Path $promptDir "plan-feature.prompt.md") -Value ($PromptPlanFeature.TrimEnd() + "`n") -NoNewline
    Write-Utf8NoBomFile -Path (Join-Path $promptDir "plan-epic.prompt.md") -Value ($PromptPlanEpic.TrimEnd() + "`n") -NoNewline

    Merge-VSCodeMcpServer -Path $vsCodeMcpPath -LauncherPath $launcherTarget
    Merge-VSCodeCopilotInstructions -SettingsPath $vsCodeSettingsPath -ContextFilePath $copilotTarget
    Merge-VSCodePromptFileLocation -SettingsPath $vsCodeSettingsPath -PromptDirectory $promptDir
}

$claudeMcpRegistered = $false
if ($configureClaudeNow) {
    Write-Host "Configuring Claude Code..."

    $claude = Get-Command "claude" -ErrorAction SilentlyContinue
    if ($null -eq $claude) {
        Write-Host "  Claude CLI not found. MCP registration is pending."
        Write-Host "  Run manually after installing Claude Code:"
        Write-Host "  claude mcp add --scope user azure-devops -- $script:McpPowerShellCommand -NoProfile -ExecutionPolicy Bypass -File `"$launcherTarget`""
    } else {
        & claude mcp add --scope user azure-devops -- $script:McpPowerShellCommand -NoProfile -ExecutionPolicy Bypass -File $launcherTarget
        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }
        $claudeMcpRegistered = $true
    }

    Merge-MarkdownBlock -Path (Join-Path $userHome ".claude\CLAUDE.md") -MarkerName "azure-devops-agents" -Content $claudeContextBlock
}

Write-Host ""
Write-Host "Done. Per-tool summary:"
if ($configureClaudeNow) {
    if ($claudeMcpRegistered) {
        Write-Host "  Claude Code : MCP registered + ~/.claude/CLAUDE.md updated"
    } else {
        Write-Host "  Claude Code : ~/.claude/CLAUDE.md updated (MCP registration pending if Claude CLI was absent)"
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
    Write-Host "Docker auth      : set ADO_MCP_AUTH_TOKEN before starting any tool, or rerun with -AuthToken <pat>."
} else {
    Write-Host "Auth defaults to azcli. Run 'az login' if needed."
    Write-Host "Service principal: set AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_TENANT_ID, then restart all tools."
}
Write-Host "Per-repo config  : add .ado-mcp.json -> { ""project"": ""YourProject"", ""team"": ""YourTeam"" }"
