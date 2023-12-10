$PSCompletions | Add-Member -MemberType ScriptMethod fn_get_config {
    try {
        $c = Get-Content -raw -path "$($PSCompletions.path.root)/env.json" | ConvertFrom-Json
    }
    catch {
        $c = @{
            root_cmd = 'psc'
            github   = 'https://github.com/abgox/PSCompletions'
            gitee    = 'https://gitee.com/abgox/PSCompletions'
            language = $PSCompletions.lang
            update   = 1
            LRU      = 5
        }
        $c | ConvertTo-Json | Out-File "$($PSCompletions.path.root)/env.json"
    }
    return @{
        root_cmd = $c.root_cmd
        github   = $c.github
        gitee    = $c.gitee
        language = $c.language
        update   = $c.update
        LRU      = $c.LRU
    }
}
$PSCompletions | Add-Member -MemberType ScriptMethod fn_set_config {
    param ([string]$k, [string]$v)
    $c = $PSCompletions.fn_get_config()
    $c.$k = $v
    $c | ConvertTo-Json | Out-File "$($PSCompletions.path.root)/env.json"
}
