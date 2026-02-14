#Requires -Version 7.0

param(
    [string]$CompletionName
)

Set-StrictMode -Off

$completion_name = $CompletionName

$textPath = "$PSScriptRoot/language/$PSCulture.json"
if (!(Test-Path $textPath)) {
    $textPath = "$PSScriptRoot/language/en-US.json"
}
$text = Get-Content -Path $textPath -Encoding utf8 | ConvertFrom-Json

if (!$PSCompletions) {
    Write-Host $text.'import-psc' -ForegroundColor Red
    return
}

$text = $text.'create-completion'

if (!$completion_name.Trim()) {
    $PSCompletions.write_with_color($PSCompletions.replace_content($text.invalidName))
    return
}

$root_dir = Split-Path $PSScriptRoot -Parent
$completion_dir = "$root_dir/completions/$completion_name"
if (Test-Path $completion_dir) {
    if (Test-Path "$completion_dir/config.json") {
        $PSCompletions.write_with_color($text.exist)
        return
    }
    else {
        Remove-Item -Path $completion_dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# create new completion
$PSCompletions.ensure_dir($completion_dir)
$PSCompletions.ensure_dir("$completion_dir/language")

Copy-Item "$($PSScriptRoot)/template/config.json" "$completion_dir/config.json" -Force

Copy-Item "$($PSScriptRoot)/template/language/en-US.json" "$completion_dir/language/en-US.json" -Force
Copy-Item "$($PSScriptRoot)/template/language/zh-CN.json" "$completion_dir/language/zh-CN.json" -Force
Copy-Item "$($PSScriptRoot)/template/hooks.ps1" "$completion_dir/hooks.ps1" -Force

$PSCompletions.write_with_color($PSCompletions.replace_content($text.success))
