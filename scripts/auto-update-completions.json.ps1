Set-StrictMode -Off

$completions = @{
    list = @()
}
Get-ChildItem "$PSScriptRoot\..\completions" | ForEach-Object {
    $completions.list += $_.Name
}

$completions | ConvertTo-Json -Compress | Out-File "$PSScriptRoot\..\completions.json"
