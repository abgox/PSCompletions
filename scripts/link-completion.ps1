param([string]$completion_name)

if (!$PSCompletions) {
    Write-Host "You should install PSCompletions module and import it." -ForegroundColor Red
    return
}
if (!$completion_name.Trim()) {
    $PSCompletions.write_with_color("<@Red>You should enter an available completion name.`ne.g. <@Magenta>.\scripts\link-completion.ps1 git")
    return
}
$root_dir = Split-Path $PSScriptRoot -Parent
$completion_dir = $PSCompletions.join_path($root_dir, "completions", $completion_name)
if (!(Test-Path $completion_dir)) {
    $PSCompletions.write_with_color("<@Red><@Magenta>$completion_name<@Red> isn't exist.")
    return
}

$completion_dir = "$($PSCompletions.path.completions)\$completion_name"
Remove-Item $completion_dir -Force -Recurse -ErrorAction SilentlyContinue
New-Item -ItemType SymbolicLink -Path $completion_dir -Target "$PSScriptRoot\..\completions\$completion_name" -Force
