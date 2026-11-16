#Requires -Version 7.0
<#
.SYNOPSIS
    Pre-release checklist: publish config.example.json from config.json.

.DESCRIPTION
    Runs Publish-ConfigExample.ps1, then prints reminders for version / CHANGELOG
    steps documented in ARCHITECTURE.md (section Version Bumping).
#>
[CmdletBinding()]
param(
    [switch] $WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$publishScript = Join-Path $PSScriptRoot 'Publish-ConfigExample.ps1'
if ($WhatIf) {
    & $publishScript -WhatIf
}
else {
    & $publishScript
}

Write-Host ''
Write-Host 'Release checklist (see ARCHITECTURE.md):' -ForegroundColor Cyan
Write-Host '  1. config.json — schema/menus done; configVersion bumped'
Write-Host '  2. config.example.json — published (this script)'
Write-Host '  3. console.ps1 — $script:ConsoleVersion + CHANGELOG.md'
Write-Host '  4. Feature branch, PR, merge, gh release create'
Write-Host '  5. upgrade-prod.ps1 to promote PROD'