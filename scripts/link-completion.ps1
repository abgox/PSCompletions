param(
    [string]$Name
)

Set-StrictMode -Off

$completion_name = $Name

$textPath = "$PSScriptRoot/language/$PSCulture.json"
if (!(Test-Path $textPath)) {
    $textPath = "$PSScriptRoot/language/en-US.json"
}
$text = Get-Content -Path $textPath -Encoding utf8 | ConvertFrom-Json

if (!$PSCompletions) {
    Write-Host $text."import-psc" -ForegroundColor Red
    return
}

$text = $text."link-completion"

if (!$completion_name.Trim()) {
    $PSCompletions.write_with_color($PSCompletions.replace_content($text.invalidParams))
    return
}

$completions_list = (Get-ChildItem "$PSScriptRoot\..\completions" -Directory).Name
if ($completion_name -notin $completions_list) {
    $PSCompletions.write_with_color($PSCompletions.replace_content($text.invalidName))
    return
}
$root_dir = Split-Path $PSScriptRoot -Parent
$completion_dir = "$root_dir/completions/$completion_name"
if (!(Test-Path $completion_dir)) {
    $PSCompletions.write_with_color($PSCompletions.replace_content($text.noExist))
    return
}

$test_dir = "$($PSCompletions.path.completions)\$completion_name"

if (Test-Path $test_dir) {
    $PSCompletions.write_with_color($PSCompletions.replace_content($text.exist))
    return
}

$null = New-Item -ItemType Junction -Path $test_dir -Target "$PSScriptRoot\..\completions\$completion_name" -Force

$language = $PSCompletions.get_language($completion_name)

$config = $PSCompletions.ConvertFrom_JsonAsHashtable($PSCompletions.get_raw_content("$PSScriptRoot\..\completions\$completion_name\config.json"))

if ($config.hooks -ne $null) {
    if ($null -eq $PSCompletions.data.config.comp_config[$completion_name]) {
        $PSCompletions.data.config.comp_config[$completion_name] = @{}
    }
    if ($null -eq $PSCompletions.data.config.comp_config[$completion_name].enable_hooks) {
        $PSCompletions.data.config.comp_config[$completion_name].enable_hooks = [int]$config.hooks
    }
}

if ($config.alias -eq $null) {
    $PSCompletions.data.alias[$completion_name] = @($completion_name)
    $PSCompletions.data.aliasMap[$completion_name] = $completion_name
}
else {
    $PSCompletions.data.alias[$completion_name] = $config.alias
    foreach ($a in $config.alias) {
        $PSCompletions.data.aliasMap[$a] = $completion_name
    }
}

$PSCompletions.data.list += $completion_name

$json = $PSCompletions.ConvertFrom_JsonAsHashtable($PSCompletions.get_raw_content("$PSScriptRoot\..\completions\$completion_name\language\$language.json"))

foreach ($c in $json.config) {
    if ($null -eq $PSCompletions.data.config.comp_config[$completion_name].$($c.name)) {
        $PSCompletions.data.config.comp_config[$completion_name].$($c.name) = $c.value
    }
}

$PSCompletions.data | ConvertTo-Json -Depth 100 | Out-File $PSCompletions.path.data -Encoding utf8 -Force

$PSCompletions.write_with_color($PSCompletions.replace_content($text.linkDone))
