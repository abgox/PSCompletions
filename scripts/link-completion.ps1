param([string]$completion_name)

$textPath = "$PSScriptRoot/language/$PSCulture.json"
if (!(Test-Path $textPath)) {
    $textPath = "$PSScriptRoot/language/en-US.json"
}
$text = Get-Content -Path $textPath -Encoding utf8 | ConvertFrom-Json

# $isAdmin = [bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match "S-1-5-32-544")
# if (!$isAdmin) {
#     Write-Host $text."need-admin" -ForegroundColor Red
#     return
# }

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

$completion_dir = "$($PSCompletions.path.completions)\$completion_name"
Remove-Item $completion_dir -Force -Recurse -ErrorAction SilentlyContinue
$null = New-Item -ItemType Junction -Path $completion_dir -Target "$PSScriptRoot\..\completions\$completion_name" -Force

$language = $PSCompletions.get_language($completion_name)

$config = $PSCompletions.ConvertFrom_JsonToHashtable($PSCompletions.get_raw_content("$PSScriptRoot\..\completions\$completion_name\config.json"))

$PSCompletions.data.config.comp_config.$completion_name = @{}
if ($config.hooks -ne $null) {
    $PSCompletions.data.config.comp_config.$completion_name.enable_hooks = [int]$config.hooks
}

$json = $PSCompletions.ConvertFrom_JsonToHashtable($PSCompletions.get_raw_content("$PSScriptRoot\..\completions\$completion_name\language\$language.json"))

foreach ($c in $json.config) {
    $PSCompletions.data.config.comp_config.$completion_name.$($c.name) = $c.value
}

$PSCompletions.data | ConvertTo-Json -Depth 100 | Out-File $PSCompletions.path.data -Encoding utf8 -Force


$PSCompletions.write_with_color($PSCompletions.replace_content($text.linkDone))
