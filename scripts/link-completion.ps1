#Requires -Version 7.0

param(
    [string]$CompletionName
)

Set-StrictMode -Off

$textPath = "$PSScriptRoot/language/$PSCulture.json"
if (!(Test-Path $textPath)) {
    $textPath = "$PSScriptRoot/language/en-US.json"
}
$text = Get-Content -Path $textPath -Encoding utf8 | ConvertFrom-Json

if (!$PSCompletions) {
    Write-Host $text.'import-psc' -ForegroundColor Red
    return
}

$text = $text.'link-completion'

if (!$CompletionName.Trim()) {
    $PSCompletions.write_with_color($PSCompletions.replace_content($text.invalidName))
    return
}

$completions_list = (Get-ChildItem "$PSScriptRoot\..\completions" -Directory).Name
if ($CompletionName -notin $completions_list) {
    $PSCompletions.write_with_color($PSCompletions.replace_content($text.invalidName))
    return
}
$root_dir = Split-Path $PSScriptRoot -Parent
$completion_dir = "$root_dir/completions/$CompletionName"
if (!(Test-Path $completion_dir)) {
    $PSCompletions.write_with_color($PSCompletions.replace_content($text.noExist))
    return
}

$test_dir = "$($PSCompletions.path.completions)\$CompletionName"

if ($CompletionName -eq 'psc') {
    Remove-Item $test_dir -Recurse -Force
    $null = New-Item -ItemType Junction -Path $test_dir -Target "$PSScriptRoot\..\completions\$CompletionName" -Force
    $PSCompletions.write_with_color($PSCompletions.replace_content($text.linkDone))
    return
}

if (Test-Path $test_dir) {
    $PSCompletions.write_with_color($PSCompletions.replace_content($text.exist))
    return
}

$null = New-Item -ItemType Junction -Path $test_dir -Target "$PSScriptRoot\..\completions\$CompletionName" -Force

$language = $PSCompletions.get_language($CompletionName)

$config = $PSCompletions.ConvertFrom_JsonAsHashtable($PSCompletions.get_raw_content("$PSScriptRoot\..\completions\$CompletionName\config.json"))

if ($config.hooks -ne $null) {
    if ($null -eq $PSCompletions.data.config.comp_config[$CompletionName]) {
        $PSCompletions.data.config.comp_config[$CompletionName] = @{}
    }
    if ($null -eq $PSCompletions.data.config.comp_config[$CompletionName].enable_hooks) {
        $PSCompletions.data.config.comp_config[$CompletionName].enable_hooks = [int]$config.hooks
    }
}

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

$json = $PSCompletions.ConvertFrom_JsonAsHashtable($PSCompletions.get_raw_content("$PSScriptRoot\..\completions\$CompletionName\language\$language.json"))

foreach ($c in $json.config) {
    if ($null -eq $PSCompletions.data.config.comp_config[$CompletionName].$($c.name)) {
        $PSCompletions.data.config.comp_config[$CompletionName].$($c.name) = $c.value
    }
}

$PSCompletions.data | ConvertTo-Json -Depth 100 | Out-File $PSCompletions.path.data -Encoding utf8 -Force

$PSCompletions.write_with_color($PSCompletions.replace_content($text.linkDone))
