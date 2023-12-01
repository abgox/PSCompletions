function PSCompletions {
    $arg = $args
    function _replace($data) {
        $__d__ = $data -join ''
        $__p__ = '\{\{(.*?(\})*)(?=\}\})\}\}'
        $matches = [regex]::Matches($__d__, $__p__)
        foreach ($match in $matches) {
            $__d__ = $__d__.Replace($match.Value, (Invoke-Expression $match.Groups[1].Value))
        }
        if ($__d__ -match $__p__) { $_psc.fn_replace($__d__) }else { return $__d__ }
    }
    function param_error($flag, $cmd) {
        $res = if ($flag -eq 'min') { $_psc.json.param_min }
        elseif ($flag -eq 'max') { $_psc.json.param_max }
        else { $_psc.json.param_err }
        $_psc.fn_write((_replace ($res + "`n" + $_psc.json.example.$cmd)))
    }
    function _list {
        if ($arg.Length -gt 2) {
            param_error 'max' 'list'
            return
        }
        if ($arg.Length -eq 2 -and $arg[1] -ne '--remote') {
            param_error 'err' 'list'
            return
        }
        $data = [System.Collections.Generic.List[System.Object]]@()
        if ($arg[1] -eq '--remote') {
            if (!($_psc.fn_download_list())) { throw (_replace $_psc.json.net_error) }
            $max_len = ($_psc.list  | Measure-Object -Maximum Length).Maximum
            $_psc.list | ForEach-Object {
                $status = if ($_psc.comp_cmd.$_) { $_psc.json.list_add_done }else { $_psc.json.list_add }
                $data.Add(@{
                        content = "{0,-$($max_len + 3)} {1}" -f ($_, $status)
                        color   = 'Green'
                    })
            }
            $_psc.fn_less_table($data, ('Completion', 'Status', $max_len), {
                    $_psc.fn_write((_replace $_psc.json.list_add_tip))
                })
        }
        else {
            $max_len = ($_psc.comp_cmd.keys | Measure-Object -Maximum Length).Maximum
            $_psc.comp_cmd.keys | ForEach-Object {
                $alias = if ($_psc.comp_cmd.$_ -eq $_) { '' }else { $_psc.comp_cmd.$_ }
                $data.Add(@{
                        content = "{0,-$($max_len + 3)} {1}" -f ($_, $alias)
                        color   = 'Green'
                    })
            }
            $_psc.fn_less_table($data, ('Completion', 'Alias', $max_len))
        }
    }
    function _Add {
        if ($arg.Length -lt 2) {
            param_error 'min' 'add'
            return
        }
        if (!($_psc.fn_download_list())) { return }
        $arg[1..($arg.Length - 1)] | ForEach-Object {
            if ($_ -in $_psc.list) {
                $_psc.fn_add_completion($_)
            }
            else {
                $_psc.fn_write((_replace $_psc.json.add_error))
            }
        }
    }
    function _Remove {
        if ($arg.Length -lt 2) {
            param_error 'min' 'rm'
            return
        }
        $arg[1..($arg.Length - 1)] | ForEach-Object {
            if ($_ -in $_psc.comp_cmd.keys) {
                $dir = $PSScriptRoot + '\completions\' + $_
                Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
                if (!(Test-Path($dir))) {
                    $_psc.fn_write((_replace $_psc.json.remove_done))
                }
            }
            else { $_psc.fn_write((_replace $_psc.json.remove_err)) }
        }
    }
    function _Update {
        $comp_cmd = $_psc.comp_cmd.keys | Where-Object { $_ -in $_psc.list }
        function _do {
            $update_list = [System.Collections.Generic.List[string]]@()
            try {
                foreach ($_ in $comp_cmd) {
                    $url = $_psc.url + '/completions/' + $_ + '/.guid'
                    $response = Invoke-WebRequest -Uri $url
                    if ($response.StatusCode -eq 200) {
                        $content = ($response.Content).Trim()
                        $guid = (Get-Content ($_psc.path.completions + '\' + $_ + '\.guid') -Raw).Trim()
                        if ($guid -ne $content) { $update_list.Add($_) }
                    }
                }
            }
            catch {
                $_psc.fn_write((_replace $_psc.json.net_error))
                return
            }
            $update_list | Out-File $_psc.path.update -Force -Encoding utf8
            $_psc.update = $update_list
            if ($update_list) {
                $_psc.fn_write((_replace $_psc.json.update_has))
            }
            else {
                $_psc.fn_write((_replace $_psc.json.update_no))
            }
        }
        if ($arg.Length -eq 1) { _do }
        else {
            if ($arg[1] -eq '*') {
                foreach ($_ in $_psc.update) {
                    $_psc.fn_add_completion($_, $true, $true)
                }
            }
            else {
                $arg[1..($arg.Length - 1)] | ForEach-Object {
                    if ($_ -in $comp_cmd) {
                        $_psc.fn_add_completion($_, $true, $true)
                    }
                    else {
                        $_psc.fn_write((_replace $_psc.json.update_error))
                    }
                }
            }
            _do
        }
    }
    function _Search {
        if ($arg.Length -lt 2) {
            param_error 'min' 'search'
            return
        }
        elseif ($arg.Length -gt 2) {
            param_error 'max' 'search'
            return
        }
        if (!(($_psc.fn_download_list()))) { return }
        $res = $_psc.list | Where-Object { $_ -like $arg[1] }
        if($res){
            $_psc.fn_less($res,'Cyan')
        }else{
            $_psc.fn_write((_replace $_psc.json.search_err))
        }
    }
    function _Which {
        if ($arg.Length -lt 2) {
            param_error 'min' 'which'
            return
        }
        $arg[1..($arg.Length - 1)] | ForEach-Object {
            if ($_ -in $_psc.comp_cmd.keys) {
                Write-Output ($_psc.path.completions + '\' + $_)
            }
            else {
                $_psc.fn_write((_replace $_psc.json.which_err))
            }
        }
    }
    function _alias {
        $cmd_list = @('add', 'rm', 'list', 'reset')
        if ($arg.Length -eq 1) {
            param_error 'min' 'alias'
            return
        }
        if ($arg[1] -notin $cmd_list) {
            $_psc.fn_write((_replace $_psc.json.param_errs))
            return
        }
        if ($arg[1] -eq 'add') {
            if ($arg.Length -lt 4) {
                param_error 'min' 'alias_add'
                return
            }
            elseif ($arg.Length -gt 4) {
                param_error 'max' 'alias_add'
                return
            }
        }
        if ($arg[1] -eq 'rm') {
            if ($arg.Length -lt 3) {
                param_error 'min' 'alias_rm'
                return
            }
        }
        if ($arg.Length -gt 2) {
            if ($arg[1] -eq 'list') {
                param_error 'max' 'alias_list'
                return
            }
            elseif ($arg[1] -eq 'reset') {
                param_error 'max' 'alias_reset'
                return
            }
        }
        if ($arg[1] -eq 'list') {
            $data = [System.Collections.Generic.List[System.Object]]@()
            $max_len = ($_psc.comp_cmd.keys | Measure-Object -Maximum Length).Maximum
            $_psc.comp_cmd.keys | Where-Object { $_ -ne $_psc.comp_cmd.$_ } | ForEach-Object {
                $data.Add(@{
                        content = "{0,-$($max_len + 3)} {1}" -f ($_, $_psc.comp_cmd.$_)
                        color   = 'Green'
                    })
            }
            $_psc.fn_less_table($data, ('Completion', 'Alias', $max_len))
        }
        elseif ($arg[1] -eq 'add') {
            if ($arg[2] -in $_psc.comp_cmd.Keys) {
                $cmd = (Get-Command).Name | Where-Object { $_ -eq $arg[-1] }
                $alias = (Get-Alias).Name | Where-Object { $_ -eq $arg[-1] }
                if ($cmd -or $alias) {
                    $_psc.fn_write((_replace ($_psc.json.param_err + "`n" + $_psc.json.alias_add_err)))
                    return
                }
                $arg[3] | Out-File ($_psc.path.completions + '\' + $arg[2] + '\.alias') -Force -Encoding utf8
                $_psc.fn_write((_replace $_psc.json.alias_add_done))
            }
            else {
                $_psc.fn_write((_replace $_psc.json.alias_err))
            }
        }
        elseif ($arg[1] -eq 'rm') {
            $rm_list = $arg[2..($arg.Length - 1)]
            $del_list = [System.Collections.Generic.List[string]]@()
            $error_list = [System.Collections.Generic.List[string]]@()
            $alias_list = @{}
            $_psc.comp_cmd.Keys | ForEach-Object {
                $alias = $_psc.comp_cmd.$_
                if ($_ -ne $alias) { $alias_list.$alias = $_ }
            }
            foreach ($item in $rm_list) {
                if ($item -in $alias_list.Keys) {
                    $del_list.Add($item)
                    Remove-Item ($_psc.path.completions + '\' + $alias_list.$item + '\.alias') -Force -ErrorAction SilentlyContinue
                }
                else { $error_list.Add($item) }
            }
            if ($error_list) {
                $_psc.fn_write((_replace ($_psc.json.alias_rm_err)))
            }
            if ($del_list) {
                $_psc.fn_write((_replace $_psc.json.alias_rm_done))
            }
        }
        else {
            $null = $_psc.fn_confirm($_psc.json.alias_reset_confirm, {
                    $del_list = [System.Collections.Generic.List[string]]@()
                    $reset_list = $_psc.comp_cmd.keys | Where-Object { $_psc.comp_cmd.$_ -ne $_ }
                    $alias_list = @{}
                    foreach ($_ in $reset_list) {
                        $alias = $_psc.comp_cmd.$_
                        $del_list.Add($alias)
                        $alias_list.$alias = $_
                        Remove-Item ($_psc.path.completions + '\' + $_ + '\.alias') -Force -ErrorAction SilentlyContinue
                    }
                    $_psc.fn_set_config('root_cmd', 'psc')
                    if ($del_list) {
                        $_psc.fn_write((_replace $_psc.json.alias_reset_done))
                    }
                })
        }
    }
    function _order {
        if ($arg.Length -le 2) {
            if ($arg[1] -ne 'reset') {
                param_error 'err' 'order'
            }
            else {
                param_error 'min' 'order'
            }
            return
        }
        $del_list = [System.Collections.Generic.List[string]]@()
        $err_list = [System.Collections.Generic.List[string]]@()
        if ($arg[2] -eq '*') {
            $_psc.comp_cmd.keys | ForEach-Object {
                $dir = PSCompletions which $_
                Remove-Item ($dir + '\order.json') -Force -ErrorAction SilentlyContinue
                $del_list.Add($_)
            }
        }
        else {
            $arg[2..($arg.Length - 1)] | ForEach-Object {
                if ($_ -in $_psc.comp_cmd.keys) {
                    $dir = PSCompletions which $_
                    Remove-Item ($dir + '\order.json') -Force -ErrorAction SilentlyContinue
                    $del_list.Add($_)
                }
                else {
                    $err_list.Add($_)
                }
            }
        }
        if ($del_list) {
            $_psc.fn_write((_replace $_psc.json.order_done))
        }
        if ($err_list) {
            $_psc.fn_write((_replace $_psc.json.order_err))
        }
    }

    function _Config {
        if ($arg.Length -lt 2) {
            param_error 'min' 'config'
            return
        }
        elseif ($arg.Length -gt 3) {
            param_error 'max' 'config'
            return
        }
        if ($arg.Length -eq 2) {
            if ($arg[1] -in $_psc.config.Keys) {
                Write-Output ($_psc.config[$arg[1]])
            }
            else {
                if ($arg[1] -eq 'reset') {
                    $c = [ordered]@{
                        root_cmd = 'psc'
                        github   = 'https://github.com/abgox/PSCompletions'
                        gitee    = 'https://gitee.com/abgox/PSCompletions'
                        lang     = (Get-WinSystemLocale).name
                        update   = 1
                        LRU      = 5
                    }
                    $flag = $_psc.fn_confirm($_psc.json.config_reset, {
                            [environment]::SetEnvironmentvariable('abgox_PSCompletions', (@($_psc.version, $c.root_cmd, $c.github, $c.gitee, $c.lang, $c.update, $c.LRU) -join ';'), 'User')
                        })
                    if ($flag) {
                        $_psc.config = $c
                        $_psc.fn_write((_replace $_psc.json.config_reset_done))
                    }
                    return
                }
                $_psc.fn_write((_replace $_psc.json.config_err))
            }
        }
        else {
            if ($arg[1] -in $_psc.config.Keys) {
                if ($arg[1] -eq 'root_cmd') {
                    $cmd = (Get-Command).Name | Where-Object { $_ -eq $arg[2] }
                    $alias = (Get-Alias).Name | Where-Object { $_ -eq $arg[2] }
                    if ($cmd -or $alias) {
                        $_psc.fn_write((_replace ($_psc.json.param_err + "`n" + $_psc.json.alias_add_err)))
                        return
                    }
                    $arg[2] | Out-File ($_psc.path.completions + '\PSCompletions\.alias') -Force -Encoding utf8
                }
                elseif ($arg[1] -eq 'language') {
                    $_psc.comp_data = [ordered]@{}
                }
                $_psc.fn_set_config($arg[1], $arg[2])
                $_psc.fn_write((_replace $_psc.json.config_done))
            }
            else {
                $_psc.fn_write((_replace $_psc.json.config_err))
            }
        }
    }
    function _Help {
        $_psc.fn_write((_replace $_psc.json.description))
    }

    $need_init = $true
    switch ($arg[0]) {
        'list' {
            _list
            $need_init = $null
        }
        'add' {
            _Add
        }
        'rm' {
            _Remove
        }
        'update' {
            _Update
        }
        'search' {
            _Search
            $need_init = $null
        }
        'which' {
            _Which
            $need_init = $null
        }
        'alias' {
            _alias
        }
        'order' {
            _order
        }
        'config' {
            _Config
        }
        default {
            if ($arg.Length -eq 1) {
                $_psc.fn_write((_replace $_psc.json.cmd_error))
            }
            else { _Help }
            $need_init = $null
        }
    }
    if ($need_init) {
        $_psc.fn_init()
    }
}
