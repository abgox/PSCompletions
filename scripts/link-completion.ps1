param([string]$completion_name)

if (!$PSCompletions) {
    Write-Host "You should install PSCompletions module and import it." -ForegroundColor Red
    return
}
if (!$completion_name) {
    $PSCompletions.write_with_color("<@Red>You should enter an available completion name.`ne.g. <@Magenta>.\scripts\create-completion.ps1 psc")
    return
}

$completions_list = (Get-ChildItem "$PSScriptRoot\..\completions" -Directory).Name
if ($completion_name -notin $completions_list) {
    $PSCompletions.write_with_color("<@Magenta>$completion_name<@Red> isn't an available completion name.`n<@Cyan>Available completions are: `n<@Blue>$completions_list")
    return
}
$root_dir = Split-Path $PSScriptRoot -Parent
$completion_dir = "$root_dir/completions/$completion_name"
if (!(Test-Path $completion_dir)) {
    $PSCompletions.write_with_color("<@Red><@Magenta>$completion_name<@Red> isn't exist.")
    return
}

$completion_dir = "$($PSCompletions.path.completions)\$completion_name"
Remove-Item $completion_dir -Force -Recurse -ErrorAction SilentlyContinue
New-Item -ItemType SymbolicLink -Path $completion_dir -Target "$PSScriptRoot\..\completions\$completion_name" -Force
