$invalideGuid = @()
Get-ChildItem -Path "$PSScriptRoot\..\completions\" -Directory | ForEach-Object {
    # $url = "https://raw.githubusercontent.com/abgox/PSCompletions/main/completions/$($_.Name)/guid.txt"
    $url = "https://gitee.com/abgox/PSCompletions/raw/main/completions/$($_.Name)/guid.txt"
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
    Write-Host "The following guid.txt are invalid:" -ForegroundColor Yellow
    foreach ($item in $invalideGuid) {
        Write-Host $item -ForegroundColor Red
    }
}
else {
    write-host "------------------------------------" -ForegroundColor Green
    Write-Host "All guid.txt are valid." -ForegroundColor Green
}
