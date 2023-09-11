. $PSScriptRoot\core\replace.ps1
function PSCompletions {
    $arg = $args
    function param_error {
        $res = if ($args[0] -eq 'min') { $_psc.json.param_min }
        elseif ($args[0] -eq 'max') { $_psc.json.param_max }
        else { $_psc.json.param_err }
        Write-Host (_psc_replace ($res + "`n" + $_psc.json.example.($args[1])) ) -f Red
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
            if (!(_psc_download_list)) { return }
            $max_len = ($_psc.list  | Measure-Object -Maximum Length).Maximum
            $_psc.list | ForEach-Object {
                $status = if ($_psc.comp_cmd.$_) { $_psc.json.list_add_done }else { $_psc.json.list_add }
                $data.Add(@{
                    content = "{0,-$($max_len + 3)} {1}" -f ($_, $status)
                    color   = 'Green'
                })
            }
            _psc_less $data ('Completion', 'Status', $max_len) {
                Write-Host (_psc_replace $_psc.json.list_add_tip) -f Yellow
            }
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
            _psc_less $data ('Completion', 'Alias', $max_len)
        }
    }
    function _Add {
        if ($arg.Length -lt 2) {
            param_error 'min' 'add'
            return
        }
        if (!(_psc_download_list)) { return }
        $list = $arg[1..($arg.Length - 1)]
        foreach ($_ in $list) {
            if ($_ -in $_psc.list) {
                _psc_add_completion $_
            }
            else {
                Write-Host (_psc_replace $_psc.json.add_error) -f Red
            }
        }
    }
    function _Remove {
        if ($arg.Length -lt 2) {
            param_error 'min' 'rm'
            return
        }
        $list = $arg[1..($arg.Length - 1)]
        foreach ($_ in $list) {
            if ($_ -in $_psc.comp_cmd.keys) {
                $dir = $PSScriptRoot + '\completions\' + $_
                Remove-Item $dir -Recurse -Force
                if (!(Test-Path($dir))) {
                    Write-Host (_psc_replace $_psc.json.remove_done) -f Green
                }
            }
            else { Write-Host (_psc_replace $_psc.json.remove_err) -f Red }
        }
    }
    function _Update {
        function _do {
            try {
                $update_list = [System.Collections.Generic.List[string]]@()
                foreach ($_ in $_psc.comp_cmd.keys) {
                    $url = $_psc.url + '/completions/' + $_ + '/.guid'
                    $response = Invoke-WebRequest -Uri  $url
                    if ($response.StatusCode -eq 200) {
                        $content = ($response.Content).Trim()
                        $guid = (Get-Content ($_psc.path.completions + '\' + $_ + '\.guid') -Raw).Trim()
                        if ($guid -ne $content) { $update_list.Add($_) }
                    }
                }
                $update_list | Out-File $_psc.path.update -Force -Encoding utf8
                $_psc.update = $update_list
                if ($arg.Length -gt 1) {
                    Write-Host '----------' -f Cyan
                }
                if ($update_list) {
                    Write-Host (_psc_replace $_psc.json.update_info_can) -f Yellow
                    Write-Host (_psc_replace $_psc.update) -f Green
                }
                else {
                    Write-Host (_psc_replace $_psc.json.update_info_no) -f Green
                }
            }
            catch {
                Write-Host (_psc_replace $_psc.json.error) -f Red
            }

        }
        if ($arg.Length -eq 1) {
            _do
        }
        else {
            if ($arg[1] -eq '*') {
                foreach ($_ in $_psc.update) {
                    _psc_add_completion $_ $true $true
                }
            }
            else {
                $list = $arg[1..($arg.Length - 1)]
                foreach ($_ in $list) {
                    if ($_ -in $_psc.comp_cmd.keys) {
                        _psc_add_completion $_ $true $true
                    }
                    else {
                        Write-Host (_psc_replace $_psc.json.update_error) -f Red
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
        if (!(_psc_download_list)) { return }
        $result = [System.Collections.Generic.List[System.Object]]@()
        $_psc.list | Where-Object { $_ -like $arg[1] } | ForEach-Object {
            $result.Add(@{
                content = $_
                color   = 'Green'
            })
        }
        _psc_less $result '' {
            Write-Host (_psc_replace $_psc.json.search) -f Yellow
        }
    }
    function _Which {
        if ($arg.Length -lt 2) {
            param_error 'min' 'which'
            return
        }
        $list = $arg[1..($arg.Length - 1)]
        foreach ($_ in $list) {
            if ($_ -in $_psc.comp_cmd.keys) {
                Write-Output ($_psc.path.completions + '\' + $_)
            }
            else {
                Write-Host (_psc_replace $_psc.json.which_err) -f Red
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
            Write-Host (_psc_replace $_psc.json.param_errs) -f Red
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
            _psc_less $data ('Completion', 'Alias', $max_len)
        }
        elseif ($arg[1] -eq 'add') {
            if ($arg[2] -in $_psc.comp_cmd.Keys) {
                $cmd = (Get-Command).Name | Where-Object { $_ -eq $arg[-1] }
                $alias = (Get-Alias).Name | Where-Object { $_ -eq $arg[-1] }
                if ($cmd -or $alias) {
                    param_error 'err' 'alias_add_err'
                    return
                }
                $arg[3] | Out-File ($_psc.path.completions + '\' + $arg[2] + '\.alias') -Force -Encoding utf8
                Write-Host (_psc_replace $_psc.json.alias_add_done) -f Green
            }
            else {
                Write-Host (_psc_replace $_psc.json.alias_err) -f Red
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
            foreach ($_ in $rm_list) {
                if ($_ -in $alias_list.Keys) {
                    $del_list.Add($_ + '(' + $alias_list.$_ + ')' + ' ')
                    Remove-Item ($_psc.path.completions + '\' + $alias_list.$_ + '\.alias') -Force
                }
                else { $error_list.Add($_) }
            }
            if ($error_list) {
                Write-Host (_psc_replace ($_psc.json.alias_rm_err)) -f Red
            }
            if ($del_list) {
                Write-Host (_psc_replace $_psc.json.alias_rm_done) -f Green
            }
        }
        else {
            _psc_confirm $_psc.json.alias_reset_confirm {
                $del_list = @()
                $alias_list = $_psc.comp_cmd.keys | Where-Object { $_psc.comp_cmd.$_ -ne $_ }
                foreach ($_ in $alias_list) {
                    $del_list.Add($_psc.comp_cmd.$_ + '(' + $_ + ')')
                    Remove-Item ($_psc.path.completions + '\' + $_ + '\.alias') -Force
                }
                _psc_set_config 'root_cmd' 'psc'
                if ($del_list) {
                    Write-Host (_psc_replace $_psc.json.alias_reset_done) -f Green
                }
            }
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
                    _psc_confirm $_psc.json.config_reset {
                        $root_cmd = 'psc'
                        $github = 'https://github.com/abgox/PSCompletions'
                        $gitee = 'https://gitee.com/abgox/PSCompletions'
                        $language = (Get-WinSystemLocale).name
                        $update = 1
                        [environment]::SetEnvironmentvariable('abgox_PSCompletions', (@($_psc.version, $root_cmd, $github, $gitee, $language, $update) -join ';'), 'User')
                    }
                    Write-Host (_psc_replace $_psc.json.config_reset_done) -f Green
                    return
                }
                Write-Host (_psc_replace $_psc.json.config_err) -f Red
            }
        }
        else {
            if ($arg[1] -in $_psc.config.Keys) {
                if ($arg[1] -eq 'root_cmd') {
                    $cmd = (Get-Command).Name | Where-Object { $_ -eq $arg[2] }
                    $alias = (Get-Alias).Name | Where-Object { $_ -eq $arg[2] }
                    if ($cmd -or $alias) {
                        param_error 'err' 'alias_add_err'
                        return
                    }
                    $arg[2] | Out-File ($_psc.path.completions + '\PSCompletions\.alias') -Force -Encoding utf8
                }
                _psc_set_config $arg[1] $arg[2]
                Write-Host (_psc_replace $_psc.json.config_done) -f Green
            }
            else {
                Write-Host (_psc_replace $_psc.json.config_err) -f Red
            }
        }
    }
    function _Help {
        Write-Host (_psc_replace $_psc.json.description) -f DarkCyan
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
        'config' {
            _Config
        }
        default {
            if ($arg.Length -eq 1) {
                Write-Host (_psc_replace $_psc.json.cmd_error) -f Red
            }
            else { _Help }
            $need_init = $null
        }
    }
    if ($need_init) {
        PSCompletions_init
    }
}
