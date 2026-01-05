#Requires -Version 7.0

param(
    [string[]]$CompletionList
)

Set-StrictMode -Off

$textPath = "$PSScriptRoot/language/$PSCulture.json"
if (!(Test-Path $textPath)) {
    $textPath = "$PSScriptRoot/language/en-US.json"
}
$text = Get-Content -Path $textPath -Encoding utf8 | ConvertFrom-Json

if (!$PSCompletions) {
    Write-Host $text."import-psc" -ForegroundColor Red
    return
}

$text = $text."update-guid"


if (!$CompletionList) {
    $PSCompletions.write_with_color($PSCompletions.replace_content($text.invalidParams))
    return
}

$root_dir = Split-Path $PSScriptRoot -Parent

foreach ($completion in $CompletionList) {
    $completion_dir = [System.IO.Path]::Combine($root_dir, 'completions', $completion)
    if (Test-Path $completion_dir) {
        $completion = Split-Path $completion_dir -Leaf
        $PSCompletions.write_with_color($PSCompletions.replace_content($text.updateGuid))
        @{ guid = [System.Guid]::NewGuid().Guid } | ConvertTo-Json | Out-File "$completion_dir/guid.json" -Encoding utf8 -Force
    }
}
