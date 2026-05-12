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
    Write-Warning "Docker MCP mode is experimental. Use the default global-binary mode where possible." 2>&1 | Out-Host
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
    & npx -y @azure-devops/mcp @binArgs
}
exit $LASTEXITCODE
