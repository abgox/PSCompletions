param([string]$completion_name)

if (!$PSCompletions) {
    Write-Host "You should install PSCompletions module and import it." -ForegroundColor Red
    return
}
if (!$completion_name.Trim()) {
    $PSCompletions.write_with_color("<@Red>You should enter an available completion name.`ne.g. <@Magenta>.\scripts\create-completion.ps1 test")
    return
}

$path_guide = "$($PSScriptRoot)/template/guide/$($PSCompletions.language).json"

if (Test-Path $path_guide) {
    $guide = Get-Content -Path $path_guide -Encoding utf8 | ConvertFrom-Json
}
else {
    $guide = Get-Content -Path "$($PSScriptRoot)/template/guide/en-US.json" -Encoding utf8 | ConvertFrom-Json
}

$root_dir = Split-Path $PSScriptRoot -Parent
$completion_dir = "$root_dir/completions/$completion_name"
if (Test-Path $completion_dir) {
    $PSCompletions.write_with_color($guide.exist)
    return
}

# create new completion
$PSCompletions.ensure_dir($completion_dir)
$PSCompletions.ensure_dir("$completion_dir/language")

[System.Guid]::NewGuid().Guid | Out-File "$completion_dir\guid.txt" -Encoding utf8 -Force

Copy-Item "$($PSScriptRoot)/template/config.json" "$completion_dir/config.json" -Force

Copy-Item "$($PSScriptRoot)/template/language/en-US.json" "$completion_dir/language/en-US.json" -Force
Copy-Item "$($PSScriptRoot)/template/language/zh-CN.json" "$completion_dir/language/zh-CN.json" -Force
Copy-Item "$($PSScriptRoot)/template/hooks.ps1" "$completion_dir/hooks.ps1" -Force

$test_dir = Join-Path $PSCompletions.path.completions $completion_name
Remove-Item $test_dir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType SymbolicLink -Path $test_dir -Target $completion_dir > $null
$PSCompletions.write_with_color($PSCompletions.replace_content($guide.success))

$PSCompletions.data.list += $completion_name
$PSCompletions.data.alias.$completion_name = $completion_name
$PSCompletions.data.aliasMap.$completion_name = $completion_name
$PSCompletions.data.config.comp_config.$completion_name = @{
    enable_hooks = 1
}
$PSCompletions.data | ConvertTo-Json -Depth 100 | Out-File $PSCompletions.path.data -Encoding utf8 -Force
