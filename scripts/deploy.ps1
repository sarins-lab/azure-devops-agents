param(
    [string]$DockerImage = "",
    [switch]$BuildDocker,
    [switch]$PushDocker,
    [switch]$Publish,
    [switch]$AllowDirty,
    [string]$Remote = "origin"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$dryRun = -not $Publish.IsPresent

function Invoke-External {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [switch]$ReadOnly
    )

    Write-Host (">> {0} {1}" -f $FilePath, ($Arguments -join " "))

    if ($dryRun -and -not $ReadOnly) {
        Write-Host "   dry-run: skipped"
        return
    }

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

function Test-PowerShellFile {
    param([string]$Path)

    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $Path), [ref]$tokens, [ref]$errors) > $null
    if ($errors.Count -gt 0) {
        $errors | Format-List
        throw "PowerShell syntax validation failed: $Path"
    }

    Write-Host "OK syntax: $Path"
}

function Test-JsonFile {
    param([string]$Path)

    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json > $null
    Write-Host "OK JSON: $Path"
}

function Test-NodeFile {
    param([string]$Path)

    Invoke-External -FilePath "node" -Arguments @("--check", $Path) -ReadOnly
}

function Get-BashCommand {
    $candidates = @(
        "C:\Program Files\Git\bin\bash.exe",
        "C:\Program Files\Git\usr\bin\bash.exe"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    $bash = Get-Command "bash" -ErrorAction SilentlyContinue
    if ($null -ne $bash) {
        return $bash.Source
    }

    return $null
}

function Test-BashFile {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($script:bashCommand)) {
        Write-Host "SKIP bash syntax: $Path (bash not found)"
        return
    }

    Invoke-External -FilePath $script:bashCommand -Arguments @("-n", $Path) -ReadOnly
}

Set-Location -LiteralPath $repoRoot
$script:bashCommand = Get-BashCommand

Write-Host "Azure DevOps Planning Assistant deployment"
if ($dryRun) {
    Write-Host "Mode: dry-run. Pass -Publish to create tags or push artifacts."
} else {
    Write-Host "Mode: publish"
}
Write-Host ""

if ($Publish -and -not $AllowDirty) {
    $status = git status --porcelain
    if (-not [string]::IsNullOrWhiteSpace(($status -join "`n"))) {
        throw "Working tree is dirty. Commit or stash changes, or rerun with -AllowDirty."
    }
}

Test-PowerShellFile -Path "scripts\install.ps1"
Test-PowerShellFile -Path "scripts\install-ado-mcp-user.ps1"
Test-PowerShellFile -Path "scripts\ado-mcp-launcher.ps1"
Test-PowerShellFile -Path "scripts\deploy.ps1"
Test-BashFile -Path "scripts\install.sh"
Test-BashFile -Path "scripts\install-ado-mcp-user.sh"
Test-BashFile -Path "scripts\ado-mcp-launcher.sh"
Test-NodeFile -Path "scripts\ado-mcp-launcher.mjs"

Test-JsonFile -Path ".mcp.json"
Test-JsonFile -Path ".claude-plugin\plugin.json"
Test-JsonFile -Path ".claude-plugin\marketplace.json"
Test-JsonFile -Path ".agents\plugins\marketplace.json"
Test-JsonFile -Path "plugins\azure-devops-agents-codex\.codex-plugin\plugin.json"
Test-JsonFile -Path "plugins\azure-devops-agents-vscode\package.json"

Invoke-External -FilePath "claude" -Arguments @("plugin", "validate", ".claude-plugin\marketplace.json") -ReadOnly

if ($Publish) {
    Invoke-External -FilePath "claude" -Arguments @("plugin", "tag", "--remote", $Remote, "--push", ".")
} else {
    Invoke-External -FilePath "claude" -Arguments @("plugin", "tag", "--dry-run", "--force", ".") -ReadOnly
}

if ($BuildDocker -or -not [string]::IsNullOrWhiteSpace($DockerImage)) {
    if ([string]::IsNullOrWhiteSpace($DockerImage)) {
        throw "Docker image name is required when -BuildDocker is used. Pass -DockerImage <registry/image:tag>."
    }

    Invoke-External -FilePath "docker" -Arguments @("build", "-t", $DockerImage, ".\docker")

    if ($PushDocker) {
        Invoke-External -FilePath "docker" -Arguments @("push", $DockerImage)
    }
}

Write-Host ""
if ($dryRun) {
    Write-Host "Dry-run completed. No deployment artifacts were pushed."
} else {
    Write-Host "Deployment completed."
}
