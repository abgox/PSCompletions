$PSCompletions | Add-Member -MemberType ScriptMethod fn_get_config {
    $c = $PSCompletions.fn_get_raw_content("$($PSCompletions.path.root)/env.json") | ConvertFrom-Json

    $config = [ordered]@{}

    $default = [ordered]@{
        root_cmd       = 'psc'
        github         = 'https://github.com/abgox/PSCompletions'
        gitee          = 'https://gitee.com/abgox/PSCompletions'
        language       = $PSCompletions.lang
        update         = 1
        LRU            = 5
        run_with_admin = 1
        module_update  = 1
        sym            = [char]::ConvertFromUtf32(128516)
        sym_wr         = [char]::ConvertFromUtf32(128526)
        sym_opt        = [char]::ConvertFromUtf32(129300)
    }
    $need_set = $false
    foreach ($key in $default.Keys) {
        if ($key -notin $c.PSObject.Properties.Name) {
            $need_set = $true
            $config.$key = $default[$key]
        }
        else {
            $config.$key = $c.$key
        }
    }
    if ($need_set) {
        $config | ConvertTo-Json | Out-File "$($PSCompletions.path.root)/env.json"
    }

    if ($config.update -eq $PSCompletions.version) {
        $config.update = 1
    }

    return $config
}
$PSCompletions | Add-Member -MemberType ScriptMethod fn_set_config {
    param ([string]$k, [string]$v)
    $c = $PSCompletions.fn_get_config()
    $c.$k = $v
    $c | ConvertTo-Json | Out-File "$($PSCompletions.path.root)/env.json"
}
