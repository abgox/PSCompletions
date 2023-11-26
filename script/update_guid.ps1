$comp_name = (Get-ChildItem "$PSScriptRoot\..\completions").BaseName
$comp_name | % {
    $_psc.fn_confirm(
        "是否更新 $_ 的.Guid",
        {
            (New-Guid).Guid | Out-File "$PSScriptRoot\..\completions\$_\.guid"
            write-host "已更新 $_ 的.Guid" -f Cyan
        }
    )
}
