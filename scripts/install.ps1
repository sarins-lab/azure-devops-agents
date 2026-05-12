param(
    [Parameter(Mandatory = $true)]
    [string]$Organization,
    [ValidateSet("All", "Claude", "Codex", "VSCode")]
    [string[]]$Clients = @("All"),
    [ValidateSet("npx", "docker")]
    [string]$Mode = "npx",
    [string]$Authentication = "azcli",
    [string[]]$Domains = @("core", "work", "work-items", "repositories", "wiki"),
    [string]$Project = $env:ADO_MCP_PROJECT,
    [string]$Team = $env:ADO_MCP_TEAM,
    [string]$DockerImage = "",
    [string]$AuthToken = "",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$installer = Join-Path $PSScriptRoot "install-ado-mcp-user.ps1"
$installArgs = @{
    Organization   = $Organization
    Mode           = $Mode
    Authentication = $Authentication
    Domains        = $Domains
}

if (-not [string]::IsNullOrWhiteSpace($Project)) {
    $installArgs.Project = $Project
}

if (-not [string]::IsNullOrWhiteSpace($Team)) {
    $installArgs.Team = $Team
}

if (-not [string]::IsNullOrWhiteSpace($DockerImage)) {
    $installArgs.DockerImage = $DockerImage
}

if (-not [string]::IsNullOrWhiteSpace($AuthToken)) {
    $installArgs.AuthToken = $AuthToken
}

if ($Force) {
    $installArgs.Force = $true
}

$configureAll = $Clients -contains "All"
if (-not $configureAll) {
    if ($Clients -contains "Claude") { $installArgs.ConfigureClaude = $true }
    if ($Clients -contains "Codex") { $installArgs.ConfigureCodex = $true }
    if ($Clients -contains "VSCode") { $installArgs.ConfigureVSCode = $true }
}

& $installer @installArgs
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
