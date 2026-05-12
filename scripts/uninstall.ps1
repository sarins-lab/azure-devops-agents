param(
    [string[]]$Clients   = @("All"),
    [switch]$PurgeGlobal
)

$ErrorActionPreference = "Stop"
$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
& "$PSScriptRoot\uninstall-ado-mcp-user.ps1" -Clients $Clients -PurgeGlobal:$PurgeGlobal
