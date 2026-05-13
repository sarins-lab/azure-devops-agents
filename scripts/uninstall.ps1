param(
    [string[]]$Clients   = @("All"),
    [switch]$PurgeGlobal
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
& "$scriptRoot\uninstall-ado-mcp-user.ps1" -Clients $Clients -PurgeGlobal:$PurgeGlobal
