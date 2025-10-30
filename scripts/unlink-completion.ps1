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

$completion_dir = "$($PSCompletions.path.completions)\$completion_name"
if (!(Test-Path $completion_dir)) {
    $PSCompletions.write_with_color($PSCompletions.replace_content($text.noExist))
    return
}
Remove-Item $completion_dir -Force -Recurse -ErrorAction SilentlyContinue

$temp_completion_dir = "$($PSCompletions.path.temp)\completions\$completion_name"

if (Test-Path $temp_completion_dir) {
    Move-Item $temp_completion_dir $PSCompletions.path.completions

    $isNotEmpty = (Get-ChildItem "$($PSCompletions.path.temp)\completions" -Force).Count -gt 0

    if (!$isNotEmpty) {
        Remove-Item "$($PSCompletions.path.temp)\completions" -Force -Recurse -ErrorAction SilentlyContinue
    }
}
