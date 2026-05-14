param(
    [string]$Organization = $env:ADO_MCP_ORG,
    [ValidateSet("All", "Claude", "Codex", "VSCode")]
    [string[]]$Clients = @("All"),
    [string]$Authentication = "azcli",
    [string[]]$Domains = @("core", "work", "work-items", "repositories", "wiki"),
    [string]$Project = $env:ADO_MCP_PROJECT,
    [string]$Team = $env:ADO_MCP_TEAM,
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

function Backup-FileBeforeJsonRewrite {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $backupPath = "$Path.ado-mcp.$(Get-Date -Format 'yyyyMMddHHmmssfff').bak"
    Copy-Item -LiteralPath $Path -Destination $backupPath -Force
    Write-Host "  Backed up file before JSON rewrite: $backupPath"
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

function Assert-NodeAndNpxAvailable {
    $nodeCommand = Get-Command node -ErrorAction SilentlyContinue
    if ($null -eq $nodeCommand) {
        throw "Node.js 20 or later is required for non-Docker MCP mode. Install Node.js 20+ or rerun with -DockerImage <image>."
    }

    $nodeMajorText = (& node -p "Number(process.versions.node.split('.')[0])" 2>$null)
    $nodeMajor = 0
    if ($LASTEXITCODE -ne 0 -or -not [int]::TryParse([string]$nodeMajorText, [ref]$nodeMajor) -or $nodeMajor -lt 20) {
        $nodeVersion = (& node --version 2>$null)
        if ([string]::IsNullOrWhiteSpace($nodeVersion)) {
            $nodeVersion = "unknown"
        }
        throw "Node.js 20 or later is required for non-Docker MCP mode; found $nodeVersion. Install Node.js 20+ or rerun with -DockerImage <image>."
    }

    $npxCommand = Get-Command npx -ErrorAction SilentlyContinue
    $mcpCommand = Get-Command mcp-server-azuredevops -ErrorAction SilentlyContinue
    if ($null -eq $npxCommand -and $null -eq $mcpCommand) {
        throw "Non-Docker MCP mode requires either a global mcp-server-azuredevops binary or npx in PATH. Install npm with Node.js 20+ or install @azure-devops/mcp globally."
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

if ([string]::IsNullOrWhiteSpace($DockerImage)) {
    Assert-NodeAndNpxAvailable
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

    return $value.Trim()
}

function Assert-Node20Available {
    $nodeCommand = Get-Command node -ErrorAction SilentlyContinue
    if ($null -eq $nodeCommand) {
        throw "Node.js 20 or later is required for non-Docker MCP mode. Install Node.js 20+ or configure Docker MCP mode."
    }

    $nodeMajorText = (& node -p "Number(process.versions.node.split('.')[0])" 2>$null)
    $nodeMajor = 0
    if ($LASTEXITCODE -ne 0 -or -not [int]::TryParse([string]$nodeMajorText, [ref]$nodeMajor) -or $nodeMajor -lt 20) {
        $nodeVersion = (& node --version 2>$null)
        if ([string]::IsNullOrWhiteSpace($nodeVersion)) {
            $nodeVersion = "unknown"
        }
        throw "Node.js 20 or later is required for non-Docker MCP mode; found $nodeVersion. Install Node.js 20+ or configure Docker MCP mode."
    }
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
if (-not [string]::IsNullOrWhiteSpace($organization)) {
    $organization = $organization.Trim()
}

if ([string]::IsNullOrWhiteSpace($organization)) {
    throw "Azure DevOps organization is not configured. Set ADO_MCP_ORG or create $userConfigPath."
}

$authentication = Get-StringValue -Object $userConfig -Name "authentication"
if ([string]::IsNullOrWhiteSpace($authentication)) {
    $authentication = "azcli"
}
$authentication = $authentication.Trim()

$dockerImage = Get-StringValue -Object $userConfig -Name "dockerImage"

$project = Get-StringValue -Object $userConfig -Name "project"
if ([string]::IsNullOrWhiteSpace($project)) {
    $project = $env:ADO_MCP_PROJECT
}
if (-not [string]::IsNullOrWhiteSpace($project)) {
    $project = $project.Trim()
}
$repoProject = Get-StringValue -Object $repoConfig -Name "project"
if (-not [string]::IsNullOrWhiteSpace($repoProject)) {
    $project = $repoProject
}
if (-not [string]::IsNullOrWhiteSpace($project)) {
    $env:ado_mcp_project = $project
}

$team = Get-StringValue -Object $userConfig -Name "team"
if ([string]::IsNullOrWhiteSpace($team)) {
    $team = $env:ADO_MCP_TEAM
}
if (-not [string]::IsNullOrWhiteSpace($team)) {
    $team = $team.Trim()
}
$repoTeam = Get-StringValue -Object $repoConfig -Name "team"
if (-not [string]::IsNullOrWhiteSpace($repoTeam)) {
    $team = $repoTeam
}
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
    $dockerCommand = Get-Command docker -ErrorAction SilentlyContinue
    if ($null -eq $dockerCommand) {
        throw "Docker MCP mode requires the Docker CLI in PATH. Install Docker or configure non-Docker MCP mode."
    }
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

Assert-Node20Available

$binArgs = @($organization, "--authentication", $authentication)
foreach ($domain in $domains) {
    $binArgs += "-d"
    $binArgs += [string]$domain
}

# Prefer the globally installed binary for instant startup; fall back to npx.
$mcpBin = Get-Command mcp-server-azuredevops -ErrorAction SilentlyContinue
if ($mcpBin) {
    & mcp-server-azuredevops @binArgs
} else {
    $npxBin = Get-Command npx -ErrorAction SilentlyContinue
    if ($null -eq $npxBin) {
        throw "Azure DevOps MCP launcher requires either a global mcp-server-azuredevops binary or npx in PATH. Install npm with Node.js 20+ or install @azure-devops/mcp globally."
    }
    & npx -y "@azure-devops/mcp" @binArgs
}
exit $LASTEXITCODE
'@

function Get-RemoteJoinedContent {
    param([string[]]$Paths)
    $rawBase = "https://raw.githubusercontent.com/sarins-lab/azure-devops-agents/main"
    $parts = @()
    foreach ($path in $Paths) {
        $content = (Invoke-WebRequest -Uri "$rawBase/$path" -UseBasicParsing).Content.TrimEnd()
        if (-not [string]::IsNullOrWhiteSpace($content)) {
            $parts += $content
        }
    }
    return [string]::Join("`n`n", $parts)
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

    return $value.Trim()
}

function Get-NormalizedStringValue {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    return $Value.Trim()
}

function Get-McpServerJson {
    param([string]$LauncherPath)
    return [ordered]@{
        type = "stdio"
        command = $script:McpPowerShellCommand
        args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $LauncherPath)
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
    if (-not [string]::IsNullOrWhiteSpace($DockerImage)) {
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

    Backup-FileBeforeJsonRewrite -Path $SettingsPath
    Write-Utf8NoBomFile -Path $SettingsPath -Value (($json | ConvertTo-Json -Depth 12) + "`n") -NoNewline
    Write-Host "  Added Copilot instruction reference: $SettingsPath"
}

function Remove-LegacyVSCodePromptFiles {
    param([string]$SettingsPath, [string]$PromptDirectory)

    if (Test-Path -LiteralPath $SettingsPath) {
        $json = Read-JsonFile -Path $SettingsPath
        if ($null -ne $json) {
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
                Backup-FileBeforeJsonRewrite -Path $SettingsPath
                Write-Utf8NoBomFile -Path $SettingsPath -Value (($json | ConvertTo-Json -Depth 12) + "`n") -NoNewline
            }
        }
    }

    if (Test-Path -LiteralPath $PromptDirectory) {
        Remove-Item -LiteralPath $PromptDirectory -Recurse -Force
        Write-Host "  Removed legacy VS Code prompts: $PromptDirectory"
    }
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

New-Item -ItemType Directory -Force -Path $adoHome | Out-Null
Write-Utf8NoBomFile -Path $launcherTarget -Value ($LauncherScript.TrimEnd() + "`n") -NoNewline
Write-Host "Wrote online MCP launcher: $launcherTarget"

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

$Organization = Get-NormalizedStringValue -Value $Organization
$Authentication = Get-NormalizedStringValue -Value $Authentication
$Project = Get-NormalizedStringValue -Value $Project
$Team = Get-NormalizedStringValue -Value $Team
$DockerImage = Get-NormalizedStringValue -Value $DockerImage
$Domains = @($Domains | ForEach-Object { Get-NormalizedStringValue -Value ([string]$_) } | Where-Object { $null -ne $_ })

$configChanged = $true
if ((Test-Path -LiteralPath $configTarget) -and -not $Force) {
    $existingConfig = Read-JsonFile -Path $configTarget
    $existingDocker = Get-StringValue -Object $existingConfig -Name "dockerImage"
    $incomingDocker = $DockerImage
    $dockerMismatch = ($existingDocker -ne $incomingDocker)
    $orgMismatch = (Get-StringValue -Object $existingConfig -Name "organization") -ne $Organization
    $projectMismatch = (Get-StringValue -Object $existingConfig -Name "project") -ne $Project
    $teamMismatch = (Get-StringValue -Object $existingConfig -Name "team") -ne $Team

    if ($dockerMismatch -or $orgMismatch -or $projectMismatch -or $teamMismatch) {
        throw "Config already exists with different settings. Use -Force to overwrite: $configTarget"
    }
    Write-Host "MCP config already exists and matches - skipping: $configTarget"
    $configChanged = $false
} else {
    $configAuthentication = if ([string]::IsNullOrWhiteSpace($DockerImage)) { $Authentication } else { "envvar" }
    $config = [ordered]@{ organization = $Organization; authentication = $configAuthentication }
    if (-not [string]::IsNullOrWhiteSpace($Project)) {
        $config.project = $Project
    }
    if (-not [string]::IsNullOrWhiteSpace($Team)) {
        $config.team = $Team
    }
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

if ($configChanged -or $Force) {
    Install-GlobalMcpIfMissing
} elseif ([string]::IsNullOrWhiteSpace($DockerImage)) {
    Write-Host "Global @azure-devops/mcp install check skipped because MCP config already matches. Use -Force to retry."
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

    $codexContextBlock = Get-RemoteJoinedContent -Paths @("plugins/azure-devops-agents-codex/AGENTS.md", "shared/workflows/rup-planning.md", "shared/mcp/azure-devops-tools.md")
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
    $legacyPromptDir = Join-Path $adoHome "prompts"

    $copilotContextFile = Get-RemoteJoinedContent -Paths @("plugins/azure-devops-agents-vscode/copilot-instructions.md", "shared/workflows/rup-planning.md", "shared/mcp/azure-devops-tools.md")
    Write-Utf8NoBomFile -Path $copilotTarget -Value ($copilotContextFile.TrimEnd() + "`n") -NoNewline

    Merge-VSCodeMcpServer -Path $vsCodeMcpPath -LauncherPath $launcherTarget
    Merge-VSCodeCopilotInstructions -SettingsPath $vsCodeSettingsPath -ContextFilePath $copilotTarget
    Remove-LegacyVSCodePromptFiles -SettingsPath $vsCodeSettingsPath -PromptDirectory $legacyPromptDir
}

if ($configureClaudeNow) {
    Write-Host "Configuring Claude Code..."

    $pluginDir = Join-Path $adoHome "plugin"
    $rawBase = "https://raw.githubusercontent.com/sarins-lab/azure-devops-agents/main"

    $filesToDownload = @(
        ".claude-plugin/plugin.json",
        ".claude-plugin/marketplace.json",
        ".mcp.json",
        "scripts/ado-mcp-launcher.mjs",
        "scripts/ado-mcp-launcher.sh",
        "agents/stakeholder-analyst-agent.md",
        "agents/requirements-analyst-agent.md",
        "agents/ux-designer-agent.md",
        "agents/solution-architect-agent.md",
        "agents/technical-writer-agent.md",
        "agents/delivery-planner-agent.md",
        "agents/implementation-lead-agent.md"
    )

    Write-Host "  Downloading plugin files from GitHub..."
    $dlOk = $true
    foreach ($file in $filesToDownload) {
        $dest = Join-Path $pluginDir ($file -replace "/", "\")
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
        try {
            Invoke-WebRequest -Uri "$rawBase/$file" -OutFile $dest -UseBasicParsing
        } catch {
            Write-Warning "  Failed to download $file — skipping Claude plugin install."
            $dlOk = $false
            break
        }
    }

    if ($dlOk) {
        $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
        if ($null -eq $claudeCmd) {
            Write-Host "  Claude CLI not found. Run manually after installing Claude Code:"
            Write-Host "    claude plugin marketplace add --scope user `"$pluginDir`""
            Write-Host "    claude plugin install --scope user azure-devops-agents-claude@azure-devops-agents"
        } else {
            $marketplaceList = & claude plugin marketplace list 2>&1
            if ($marketplaceList -match 'azure-devops-agents') {
                Write-Host "  Claude marketplace already registered: azure-devops-agents"
            } else {
                & claude plugin marketplace add --scope user $pluginDir
                Write-Host "  Registered Claude marketplace: azure-devops-agents"
            }

            $pluginList = & claude plugin list 2>&1
            if ($pluginList -match 'azure-devops-agents-claude') {
                Write-Host "  Claude plugin already installed: azure-devops-agents-claude"
            } else {
                & claude plugin install --scope user azure-devops-agents-claude@azure-devops-agents
                Write-Host "  Installed Claude plugin: azure-devops-agents-claude"
            }

            $claudeSettingsPath = Join-Path $userHome ".claude\settings.json"
            if (Test-Path -LiteralPath $claudeSettingsPath) {
                try {
                    $rawSettings = Get-Content -LiteralPath $claudeSettingsPath -Raw
                    $settings = ConvertFrom-JsonOrJsonC -Content $rawSettings -Path $claudeSettingsPath
                    if ($null -ne $settings) {
                        $disabled = $settings.PSObject.Properties["disabledMcpjsonServers"]
                        if ($null -ne $disabled -and $disabled.Value -contains "azure-devops") {
                            $filtered = @($disabled.Value | Where-Object { $_ -ne "azure-devops" })
                            if ($filtered.Count -eq 0) { $settings.PSObject.Properties.Remove("disabledMcpjsonServers") }
                            else { $disabled.Value = $filtered }
                            Backup-FileBeforeJsonRewrite -Path $claudeSettingsPath
                            Write-Utf8NoBomFile -Path $claudeSettingsPath -Value (($settings | ConvertTo-Json -Depth 12) + "`n") -NoNewline
                            Write-Host "  Enabled plugin MCP server in Claude settings: $claudeSettingsPath"
                        }
                    }
                } catch {
                    Write-Warning "  Could not parse $claudeSettingsPath — remove disabledMcpjsonServers manually."
                }
            }
        }
    }

    $claudeContextBlock = Get-RemoteJoinedContent -Paths @("plugins/azure-devops-agents-claude/CLAUDE.md", "shared/workflows/rup-planning.md", "shared/mcp/azure-devops-tools.md")
    Merge-MarkdownBlock -Path (Join-Path $userHome ".claude\CLAUDE.md") -MarkerName "azure-devops-agents" -Content $claudeContextBlock
}

Write-Host ""
Write-Host "Done. Client summary:"
if ($configureClaudeNow) {
    Write-Host "  Claude Code : plugin installed + ~/.claude/CLAUDE.md updated"
}
if ($configureCodexNow) {
    Write-Host "  Codex       : MCP registered + ~/.codex/AGENTS.md updated"
}
if ($configureVSCodeNow) {
    Write-Host "  VS Code     : MCP registered + Copilot instruction added"
}
Write-Host ""
if (-not [string]::IsNullOrWhiteSpace($DockerImage)) {
    Write-Host "Docker auth      : set ADO_MCP_AUTH_TOKEN before starting any tool, or rerun with -AuthToken <pat>."
} else {
    Write-Host "Auth defaults to azcli. Run 'az login' if needed."
    Write-Host "Service principal: set AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_TENANT_ID, then restart all tools."
}
Write-Host "Per-repo config  : add .ado-mcp.json -> { ""project"": ""YourProject"", ""team"": ""YourTeam"" }"
Write-Host "Project default  : stored in ~/.ado-mcp/config.json; repo .ado-mcp.json overrides it when present."
