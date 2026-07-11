#Requires -Version 7.0

param(
    [string]$CompletionName,
    [switch]$AddHooks
)

Set-StrictMode -Off

$textPath = "$PSScriptRoot/language/$PSCulture.json"
if (!(Test-Path $textPath)) {
    $textPath = "$PSScriptRoot/language/en-US.json"
}
$text = Get-Content -Path $textPath -Encoding utf8 | ConvertFrom-Json

if (!$PSCompletions) { . $PSScriptRoot\..\module\PSCompletions\PSCompletions.ps1 }

$text = $text.'create-completion'

if (!$CompletionName.Trim()) {
    $PSCompletions.write_with_color($PSCompletions.replace_content($text.invalidName))
    return
}

$root_dir = Split-Path $PSScriptRoot -Parent
$completion_dir = "$root_dir/completions/$CompletionName"
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

$config = [ordered]@{
    language = @('en-US', 'zh-CN')
}
Copy-Item "$($PSScriptRoot)/template/language/en-US.json" "$completion_dir/language/en-US.json" -Force
Copy-Item "$($PSScriptRoot)/template/language/zh-CN.json" "$completion_dir/language/zh-CN.json" -Force

if ($AddHooks) {
    $config.hooks = $true
    Copy-Item "$($PSScriptRoot)/template/hooks.ps1" "$completion_dir/hooks.ps1" -Force
}
$config | ConvertTo-Json | Out-File "$completion_dir/config.json" -Force

if ($AddHooks) {
    $PSCompletions.write_with_color($PSCompletions.replace_content($text.successWithHooks))
}
else {
    $PSCompletions.write_with_color($PSCompletions.replace_content($text.success))
}
