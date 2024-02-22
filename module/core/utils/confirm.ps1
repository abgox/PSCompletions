$PSCompletions | Add-Member -MemberType ScriptMethod fn_confirm {
    param ([string]$tip, [scriptblock]$confirm_event)
    $PSCompletions.fn_write($PSCompletions.fn_replace($tip))
    $choice = $host.UI.RawUI.ReadKey('NoEcho, IncludeKeyDown')
    if ($choice.Character -eq 13) {
        & $confirm_event
        return $true
    }
    else {
        $PSCompletions.fn_write($PSCompletions.fn_replace($PSCompletions.json.cancel))
        return $false
    }
}
