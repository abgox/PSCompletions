param([string]$repo)

if (!$PSCompletions) {
    Write-Host "You should install PSCompletions module and import it." -ForegroundColor Red
    return
}
if (!$repo) {
    $PSCompletions.write_with_color("<@Yellow>You should enter an available repo name.`ne.g. <@Magenta>.\scripts\check-guid-valid.ps1 gitee`n     .\scripts\check-guid-valid.ps1 github")
    return
}

$repo_list = @("github", 'gitee')
if ($repo -notin $repo_list) {
    $PSCompletions.write_with_color("<@Magenta>$repo<@Red> isn't an available repo.`ne.g. <@Magenta>.\scripts\check-guid-valid.ps1 gitee`n     .\scripts\check-guid-valid.ps1 github")
    return
}

$invalideGuid = @()

if ($repo -eq "Github") {
    $prefix_url = "https://raw.githubusercontent.com/abgox/PSCompletions/main/completions"
}
else {
    $prefix_url = "https://gitee.com/abgox/PSCompletions/raw/main/completions"
}

Get-ChildItem -Path "$PSScriptRoot\..\completions\" -Directory | ForEach-Object {
    $url = "$prefix_url/$($_.Name)/guid.txt"
    try {
        $content = Invoke-WebRequest -Uri $url
        $content = $content.Content.Trim()
        $content
        if (!($content -match "^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$")) {
            $invalideGuid += $_.Name
        }
    }
    catch {}
}
if ($invalideGuid) {
    write-host "------------------------------------" -ForegroundColor Yellow
    $PSCompletions.write_with_color("<@Yellow>The following guid.txt of <@Magenta>$repo<@Yellow> are invalid:")
    foreach ($item in $invalideGuid) {
        Write-Host $item -ForegroundColor Red
    }
}
else {
    write-host "------------------------------------" -ForegroundColor Green
    $PSCompletions.write_with_color("<@Green>All guid.txt of <@Magenta>$repo<@Green> are valid.")
}
