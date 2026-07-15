#Requires -Version 7.0

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

$text = $text.'link-completion'

foreach ($CompletionName in $CompletionList) {
    if (!$CompletionName.Trim()) {
        $PSCompletions.write_with_color($PSCompletions.replace_content($text.invalidName))
        continue
    }
    $completions_list = (Get-ChildItem "$PSScriptRoot\..\completions" -Directory).Name
    if ($CompletionName -notin $completions_list) {
        $PSCompletions.write_with_color($PSCompletions.replace_content($text.invalidName))
        continue
    }
    $root_dir = Split-Path $PSScriptRoot -Parent
    $completion_dir = "$root_dir/completions/$CompletionName"
    if (!(Test-Path -LiteralPath $completion_dir)) {
        $PSCompletions.write_with_color($PSCompletions.replace_content($text.noExist))
        continue
    }
    $test_dir = "$($PSCompletions.path.completions)\$CompletionName"
    if ($CompletionName -eq 'psc') {
        Remove-Item $test_dir -Recurse -Force -ErrorAction Ignore
        $null = New-Item -ItemType Junction -Path $test_dir -Target "$PSScriptRoot\..\completions\$CompletionName" -Force
        $PSCompletions.write_with_color($PSCompletions.replace_content($text.linkDone))
        continue
    }
    if (Test-Path -LiteralPath $test_dir) {
        $PSCompletions.write_with_color($PSCompletions.replace_content($text.exist))
        continue
    }
    $null = New-Item -ItemType Junction -Path $test_dir -Target "$PSScriptRoot\..\completions\$CompletionName" -Force

    $language = $PSCompletions.get_language($CompletionName)

    $config = $PSCompletions.ConvertFrom_JsonAsHashtable($PSCompletions.get_raw_content("$PSScriptRoot\..\completions\$CompletionName\config.json"))

    if ($config.hooks -ne $null) {
        if ($null -eq $PSCompletions.data.config.completion[$CompletionName]) {
            $PSCompletions.data.config.completion[$CompletionName] = @{}
        }
        if ($null -eq $PSCompletions.data.config.completion[$CompletionName].enable_hooks) {
            $PSCompletions.data.config.completion[$CompletionName].enable_hooks = [int]$config.hooks
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
        if ($null -eq $PSCompletions.data.config.completion[$CompletionName].$($c.name)) {
            $PSCompletions.data.config.completion[$CompletionName].$($c.name) = $c.value
        }
    }

    $saveData = [ordered]@{}
    foreach ($key in $PSCompletions.data.Keys) {
        if ($key -notin 'list', 'aliasMap') { $saveData[$key] = $PSCompletions.data[$key] }
    }
    $saveData | ConvertTo-Json -Depth 10 | Out-File $PSCompletions.path.data -Force -Encoding utf8

    $PSCompletions.write_with_color($PSCompletions.replace_content($text.linkDone))
}
