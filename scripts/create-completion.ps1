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

$text = $text."create-completion"

if (!$completion_name.Trim()) {
    $PSCompletions.write_with_color($PSCompletions.replace_content($text.invalidParams))
    return
}

$root_dir = Split-Path $PSScriptRoot -Parent
$completion_dir = "$root_dir/completions/$completion_name"
if (Test-Path $completion_dir) {
    $PSCompletions.write_with_color($text.exist)
    return
}

# create new completion
$PSCompletions.ensure_dir($completion_dir)
$PSCompletions.ensure_dir("$completion_dir/language")

@{ guid = [System.Guid]::NewGuid().Guid } | ConvertTo-Json | Out-File "$completion_dir/guid.json" -Encoding utf8 -Force

Copy-Item "$($PSScriptRoot)/template/config.json" "$completion_dir/config.json" -Force

Copy-Item "$($PSScriptRoot)/template/language/en-US.json" "$completion_dir/language/en-US.json" -Force
Copy-Item "$($PSScriptRoot)/template/language/zh-CN.json" "$completion_dir/language/zh-CN.json" -Force
Copy-Item "$($PSScriptRoot)/template/hooks.ps1" "$completion_dir/hooks.ps1" -Force

$test_dir = Join-Path $PSCompletions.path.completions $completion_name
Remove-Item $test_dir -Recurse -Force -ErrorAction SilentlyContinue
$null = New-Item -ItemType Junction -Path $test_dir -Target $completion_dir
$PSCompletions.write_with_color($PSCompletions.replace_content($text.success))

$PSCompletions.data.list += $completion_name
$PSCompletions.data.alias.$completion_name = @($completion_name)
$PSCompletions.data.aliasMap.$completion_name = $completion_name

$PSCompletions.data.config.comp_config.$completion_name = @{
    enable_hooks = 1
}
$PSCompletions.data | ConvertTo-Json -Depth 100 | Out-File $PSCompletions.path.data -Encoding utf8 -Force
