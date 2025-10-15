param(
    [array]$completion_list
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


if (!$completion_list) {
    $PSCompletions.write_with_color($PSCompletions.replace_content($text.invalidParams))
    return
}

$root_dir = Split-Path $PSScriptRoot -Parent
$path_list = $completion_list | ForEach-Object {
    $completion_dir = $root_dir + "/completions/" + $_
    if (Test-Path $completion_dir) {
        $completion_dir
    }
}
if ($path_list) {
    foreach ($path in $path_list) {
        $PSCompletions.write_with_color($PSCompletions.replace_content($text.updateGuid))
        (New-Guid).Guid | Out-File "$path/guid.txt" -Force
    }
    return
}

(Get-ChildItem "$PSScriptRoot/../completions").BaseName | Out-GridView -OutputMode Multiple -Title $PSCompletions.replace_content($text.GridViewTip) | ForEach-Object {
    (New-Guid).Guid | Out-File "$PSScriptRoot/../completions/$_/guid.txt" -Force
}
