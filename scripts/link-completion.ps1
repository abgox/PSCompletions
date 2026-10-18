#!/usr/bin/env pwsh
#Requires -Version 7.6.5

param(
    [Parameter(Position = 0, ValueFromRemainingArguments)]
    [array]$CompletionList
)

Set-StrictMode -Off

$textPath = "$PSScriptRoot/language/$PSCulture.json"
if (!(Test-Path -LiteralPath $textPath)) {
    $textPath = "$PSScriptRoot/language/en-US.json"
}
$text = Get-Content -Path $textPath -Encoding utf8 | ConvertFrom-Json

if (!$PSCompletions) {
    Write-Host $text.'import-psc' -ForegroundColor Red
    return
}

. $PSScriptRoot/utils.ps1

$PSCompletions.initialize()

# Junctions are Windows-only and need no elevation; other platforms only have symbolic links.
$linkType = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }

$text = $text.'link-completion'

foreach ($CompletionName in $CompletionList) {
    if (!$CompletionName.Trim()) {
        $PSCompletions.write_with_color((Format-PscText $text.invalidName @{ CompletionsList = ((Get-ChildItem "$PSScriptRoot/../completions" -Directory).Name -join ' ') }))
        continue
    }
    $completionsList = (Get-ChildItem "$PSScriptRoot/../completions" -Directory).Name
    if ($CompletionName -notin $completionsList) {
        $PSCompletions.write_with_color((Format-PscText $text.invalidName @{ CompletionsList = ($completionsList -join ' ') }))
        continue
    }
    $root_dir = Split-Path $PSScriptRoot -Parent
    $completion_dir = "$root_dir/completions/$CompletionName"
    if (!(Test-Path -LiteralPath $completion_dir)) {
        $PSCompletions.write_with_color((Format-PscText $text.noExist @{ CompletionName = $CompletionName }))
        continue
    }
    $testDir = Join-Path $PSCompletions.path.dir.completions $CompletionName
    if ($CompletionName -eq 'psc') {
        Remove-Item $testDir -Recurse -Force -ErrorAction Ignore
        $null = New-Item -ItemType $linkType -Path $testDir -Target "$PSScriptRoot/../completions/$CompletionName" -Force
        $PSCompletions.write_with_color((Format-PscText $text.linkDone @{ CompletionName = $CompletionName; TestDir = $testDir }))
        continue
    }
    if (Test-Path -LiteralPath $testDir) {
        $PSCompletions.write_with_color((Format-PscText $text.exist @{ CompletionName = $CompletionName }))
        continue
    }
    $null = New-Item -ItemType $linkType -Path $testDir -Target "$PSScriptRoot/../completions/$CompletionName" -Force

    $language = $PSCompletions.get_language($CompletionName)

    $config = Get-Content -Raw -LiteralPath "$PSScriptRoot/../completions/$CompletionName/config.json" -ErrorAction Stop | ConvertFrom-Json -AsHashtable

    if ($config.alias -eq $null) {
        $PSCompletions.data.alias[$CompletionName] = @($CompletionName)
        $PSCompletions.data.aliasMap[$CompletionName] = $CompletionName
    }
    else {
        $PSCompletions.data.alias[$CompletionName] = $config.alias
        foreach ($a in $config.alias) {
            $PSCompletions.data.aliasMap[$a] = $CompletionName
        }
    }

    $PSCompletions.data.list += $CompletionName

    $json = Get-Content -Raw -LiteralPath "$PSScriptRoot/../completions/$CompletionName/language/$language.json" -ErrorAction Stop | ConvertFrom-Json -AsHashtable

    foreach ($c in $json.config) {
        if ($null -eq $PSCompletions.data.config.completion) {
            $PSCompletions.data.config.completion = @{}
        }
        if ($null -eq $PSCompletions.data.config.completion[$CompletionName]) {
            $PSCompletions.data.config.completion[$CompletionName] = @{}
        }
        if ($null -eq $PSCompletions.data.config.completion[$CompletionName].$($c.name)) {
            $PSCompletions.data.config.completion[$CompletionName].$($c.name) = $c.value
        }
    }

    $saveData = [ordered]@{}
    foreach ($key in $PSCompletions.data.Keys) {
        if ($key -notin 'list', 'aliasMap') { $saveData[$key] = $PSCompletions.data[$key] }
    }
    $saveData | ConvertTo-Json -Depth 10 | Out-File $PSCompletions.path.file.settings -Force -Encoding utf8

    $PSCompletions.write_with_color((Format-PscText $text.linkDone @{ CompletionName = $CompletionName; TestDir = $testDir }))
}
