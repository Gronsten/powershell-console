#Requires -Version 7.0
<#
.SYNOPSIS
    Publish sanitized config.example.json from the DEV working config.json.

.DESCRIPTION
    Run before committing a release that changes config schema or menus.
    Source of truth: _dev/config.json (gitignored). Output: config.example.json (tracked).

.PARAMETER DevConfigPath
    Path to config.json (default: ../config.json next to console.ps1).

.PARAMETER ExampleConfigPath
    Path to config.example.json (default: ../config.example.json).

.PARAMETER ManifestPath
    Publishing rules and placeholders (default: config-publish.manifest.json in this folder).

.PARAMETER WhatIf
    Show what would be written without saving.

.PARAMETER PassThru
    Return the published hashtable instead of writing a file.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string] $DevConfigPath,
    [string] $ExampleConfigPath,
    [string] $ManifestPath,
    [switch] $PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = $PSScriptRoot
$repoRoot = Split-Path $scriptRoot -Parent

if (-not $DevConfigPath) { $DevConfigPath = Join-Path $repoRoot 'config.json' }
if (-not $ExampleConfigPath) { $ExampleConfigPath = Join-Path $repoRoot 'config.example.json' }
if (-not $ManifestPath) { $ManifestPath = Join-Path $scriptRoot 'config-publish.manifest.json' }

function Get-ConfigHashtable {
    param([Parameter(Mandatory)][string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Config file not found: $Path"
    }
    $raw = [System.IO.File]::ReadAllText($Path)
    return $raw | ConvertFrom-Json -AsHashtable
}

function Copy-HashtableShallow {
    param([hashtable] $Source)
    $out = @{}
    foreach ($k in $Source.Keys) { $out[$k] = $Source[$k] }
    return $out
}

function Copy-ObjectGraph {
    param($Object)
    if ($null -eq $Object) { return $null }
    $json = $Object | ConvertTo-Json -Depth 100 -Compress
    return $json | ConvertFrom-Json -AsHashtable
}

function Merge-HashtableFromDev {
    param(
        [hashtable] $Target,
        [hashtable] $Dev,
        [string[]] $Keys
    )
    foreach ($key in $Keys) {
        if (-not $Dev.ContainsKey($key)) { continue }
        $Target[$key] = Copy-ObjectGraph $Dev[$key]
    }
}

function Apply-PathPlaceholders {
    param(
        [hashtable] $Published,
        [hashtable] $Dev,
        [hashtable] $Manifest
    )
    $placeholders = $Manifest.pathPlaceholders
    $deprecated = @($Manifest.deprecatedPathKeys | ForEach-Object { $_ })
    $devPaths = $Dev['paths']
    if ($devPaths -isnot [hashtable]) { return }

    $outPaths = @{}
    foreach ($key in $devPaths.Keys) {
        if ($deprecated -contains $key) { continue }
        if ($placeholders.ContainsKey($key)) {
            $outPaths[$key] = $placeholders[$key]
        }
        else {
            throw (
                "New paths.$key in config.json has no entry in config-publish.manifest.json " +
                'pathPlaceholders. Add a generic placeholder before publishing.'
            )
        }
    }
    $Published['paths'] = $outPaths
}

function Apply-DefaultConnectionSanitize {
    param(
        [hashtable] $Published,
        [hashtable] $Dev,
        [hashtable] $Manifest
    )
    if (-not $Dev.ContainsKey('defaultConnection')) { return }
    $conn = Copy-ObjectGraph $Dev['defaultConnection']
    foreach ($field in $Manifest.defaultConnectionBlankFields) {
        if ($conn.ContainsKey($field)) { $conn[$field] = '' }
    }
    $Published['defaultConnection'] = $conn
}

function Apply-AwsPromptIndicatorSanitize {
    param(
        [hashtable] $Published,
        [hashtable] $Dev,
        [hashtable] $Manifest,
        [hashtable] $Example
    )
    $base = @{}
    if ($Example.ContainsKey('awsPromptIndicator')) {
        $base = Copy-ObjectGraph $Example['awsPromptIndicator']
    }
    if ($Dev.ContainsKey('awsPromptIndicator')) {
        $devApi = $Dev['awsPromptIndicator']
        if ($devApi -is [hashtable] -and $devApi.ContainsKey('autoInferTerraformPaths')) {
            $base['autoInferTerraformPaths'] = $devApi['autoInferTerraformPaths']
        }
    }
    $base['directoryMappings'] = Copy-ObjectGraph $Manifest.awsPromptIndicatorDirectoryMappings
    $Published['awsPromptIndicator'] = $base
}

function Apply-BackupDevSanitize {
    param(
        [hashtable] $Published,
        [hashtable] $Manifest
    )
    if (-not $Published.ContainsKey('backupDev')) { return }
    $bd = $Published['backupDev']
    if ($bd -isnot [hashtable]) { return }
    if ($bd.ContainsKey('wip') -and $bd['wip'] -is [hashtable]) {
        $bd['wip']['excludeRemotePatterns'] = @(
            $Manifest.wipExcludeRemotePatternsExample | ForEach-Object { $_ }
        )
    }
}

function Apply-LineCounterGlobalFromDev {
    param(
        [hashtable] $Published,
        [hashtable] $Dev,
        [hashtable] $Example,
        [hashtable] $Manifest
    )
    if (-not $Manifest.lineCounterCopyGlobalExclusionsFromDev) { return }
    if (-not $Example.ContainsKey('lineCounter')) { return }
    $lc = Copy-ObjectGraph $Example['lineCounter']
    if ($Dev.ContainsKey('lineCounter') -and $Dev['lineCounter'] -is [hashtable]) {
        $devLc = $Dev['lineCounter']
        if ($devLc.ContainsKey('globalExclusions')) {
            $lc['globalExclusions'] = Copy-ObjectGraph $devLc['globalExclusions']
        }
    }
    $Published['lineCounter'] = $lc
}

function Sort-PublishedConfigKeys {
    param([hashtable] $Published)
    $keyOrder = @(
        'paths', 'defaultConnection', 'aws', 'environments', 'actionDefinitions', 'standardActions',
        'menus', 'awsAccountMenuOrder', 'awsPromptIndicator', 'lineCounter', '_execAdminMergeSnippet',
        'backupDev', 'packageManager', 'configVersion'
    )
    $ordered = [ordered]@{}
    foreach ($k in $keyOrder) {
        if ($Published.ContainsKey($k)) { $ordered[$k] = $Published[$k] }
    }
    foreach ($k in $Published.Keys) {
        if (-not $ordered.Contains($k)) { $ordered[$k] = $Published[$k] }
    }
    return $ordered
}

function ConvertTo-OrderedJson {
    param(
        $Ordered,
        [int] $Depth = 100
    )
    return ($Ordered | ConvertTo-Json -Depth $Depth)
}

function Invoke-StringSanitizeOnJson {
    param(
        [string] $Json,
        [object[]] $Patterns
    )
    $out = $Json
    foreach ($entry in $Patterns) {
        $out = [regex]::Replace($out, $entry.pattern, $entry.replacement)
    }
    return $out
}

function Test-PublishedConfigSafe {
    param(
        [string] $Json,
        [hashtable] $Manifest
    )
    foreach ($pat in $Manifest.forbiddenPatterns) {
        if ([regex]::IsMatch($Json, $pat)) {
            throw "Published JSON still matches forbidden pattern: $pat"
        }
    }
    $idMatches = [regex]::Matches($Json, '\b\d{12}\b')
    $allowed = @($Manifest.allowedAwsAccountIdsInOutput | ForEach-Object { "$_" })
    foreach ($m in $idMatches) {
        if ($allowed -notcontains $m.Value) {
            throw (
                "Published JSON contains AWS account id $($m.Value) not in allowedAwsAccountIdsInOutput. " +
                'Sanitize directoryMappings / environments before publishing.'
            )
        }
    }
}

if (-not (Test-Path -LiteralPath $ManifestPath)) {
    throw "Manifest not found: $ManifestPath"
}

$manifest = Get-ConfigHashtable -Path $ManifestPath
$dev = Get-ConfigHashtable -Path $DevConfigPath
$example = Get-ConfigHashtable -Path $ExampleConfigPath

if (-not $dev.ContainsKey('configVersion')) {
    throw 'config.json is missing configVersion. Bump it in the working config first.'
}

$published = @{}
foreach ($key in $manifest.preserveFromExampleTopLevel) {
    if ($example.ContainsKey($key)) {
        $published[$key] = Copy-ObjectGraph $example[$key]
    }
}

Merge-HashtableFromDev -Target $published -Dev $dev -Keys $manifest.copyFromDevTopLevel
Apply-PathPlaceholders -Published $published -Dev $dev -Manifest $manifest
Apply-DefaultConnectionSanitize -Published $published -Dev $dev -Manifest $manifest
Apply-AwsPromptIndicatorSanitize -Published $published -Dev $dev -Manifest $manifest -Example $example
Apply-BackupDevSanitize -Published $published -Manifest $manifest
Apply-LineCounterGlobalFromDev -Published $published -Dev $dev -Example $example -Manifest $manifest

# awsAccountMenuOrder must stay empty in the public template
if (-not $published.ContainsKey('awsAccountMenuOrder')) {
    $published['awsAccountMenuOrder'] = @()
}

$orderedPublished = Sort-PublishedConfigKeys -Published $published
$json = ConvertTo-OrderedJson -Ordered $orderedPublished -Depth 100
$json = Invoke-StringSanitizeOnJson -Json $json -Patterns $manifest.stringSanitizePatterns
Test-PublishedConfigSafe -Json $json -Manifest $manifest

$pretty = $json | ConvertFrom-Json | ConvertTo-Json -Depth 100
$pretty = $pretty -replace "`r`n", "`n"
$pretty = $pretty -replace "`n", "`r`n"

if ($PassThru) {
    return ($pretty | ConvertFrom-Json -AsHashtable)
}

$target = $ExampleConfigPath
if ($PSCmdlet.ShouldProcess($target, 'Write published config.example.json')) {
    [System.IO.File]::WriteAllText($target, $pretty)
    Write-Host "Published: $target (configVersion $($dev.configVersion))" -ForegroundColor Green
}