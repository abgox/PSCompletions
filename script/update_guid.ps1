$comp_name = (Get-ChildItem "$PSScriptRoot/../completions").BaseName
$comp_name | % {
    $null = $PSCompletions.fn_confirm(
        "是否更新 $_ 的 guid.txt",
        {
            (New-Guid).Guid | Out-File "$PSScriptRoot/../completions/$_/guid.txt"
            write-host "已更新 $_ 的 guid.txt" -f Green
        }
    )
}
