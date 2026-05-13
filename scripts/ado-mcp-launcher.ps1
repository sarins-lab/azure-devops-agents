$ErrorActionPreference = "Stop"

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
    Write-Warning "Docker MCP mode is experimental. Use the default global-binary mode where possible."
    $dockerCommand = Get-Command docker -ErrorAction SilentlyContinue
    if ($null -eq $dockerCommand) {
        throw "Docker MCP mode requires the Docker CLI in PATH. Install Docker or configure non-Docker MCP mode."
    }
    if ([string]::IsNullOrWhiteSpace($env:ADO_MCP_AUTH_TOKEN)) {
        throw "Docker MCP mode requires ADO_MCP_AUTH_TOKEN in the host environment. Set it to an Azure DevOps PAT before starting the IDE."
    }

    # Docker stdio mode uses envvar auth inside the container. Do not require local Azure CLI login.
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
        $domainStr = $domains -join ','
        $dockerArgs += "-e"
        $dockerArgs += "ADO_DOMAINS=$domainStr"
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
