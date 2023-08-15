<#
# @Author      : abgox
# @Github      : https://github.com/abgox/PSCompletions
#>
function PSCompletions {
    $arg = $args
    function _templete {
        $arg = $args
        $list = $arg[1..($arg.Length - 1)]
        foreach ($_ in $list) {
            $res += ' ' + $_
        }
        return ("`n" + '      ' + $_psc.config.root_cmd + ' ' + $arg[0] + $res)
    }
    function param_error($err, $completion = 'scoop', $example2 = (_templete ' scoop volta ...')) {
        if ($err -eq 'min') {
            $res = $_psc.json.param_min
        }
        else {
            $res = $_psc.json.param_max
        }
        Write-Host (_psc_replace $res  @{'sub_cmd' = $arg[0]; 'completion' = $completion; 'example2' = $example2 }) -f Red
    }

    function _list {
        if ($arg.Length -gt 1) {
            param_error 'max' '' ''
            return
        }
        $data = New-Object System.Collections.ArrayList
        foreach ($_ in $_psc.installed.baseName) {
            $alias = _psc_get_cmd ($_psc.completions + '\' + $_) $_
            if ($alias -eq $_) { $alias = '' }
            $data += [PSCustomObject]@{
                Completion = $_
                Alias      = $alias
            }
        }
        $data | Format-Table -AutoSize -Wrap
        Write-Host (_psc_replace $_psc.json.alias_tip) -f Yellow
    }
    function _Add {
        if ($arg.Length -lt 2) {
            param_error 'min'
            return
        }
        _psc_download_list
        $list = $arg[1..($arg.Length - 1)]
        foreach ($_ in $list) {
            if ($_ -in $_psc.list) {
                _psc_add_completion $_
            }
            else {
                Write-Host (_psc_replace $_psc.json.add_error @{'completion' = $_ }) -f Red
            }
        }
    }
    function _Remove {
        if ($arg.Length -lt 2) {
            param_error 'min'
            return
        }
        $list = $arg[1..($arg.Length - 1)]
        foreach ($_ in $list) {
            if ($_ -in $_psc.installed.BaseName) {
                $dir = $PSScriptRoot + '\completions\' + $_
                rmdir $dir -Recurse -Force
                if (!(Test-Path($dir))) {
                    Write-Host (_psc_replace $_psc.json.rm_completed @{'completion' = $_ }) -f Green
                }
            }
            else {
                Write-Host (_psc_replace $_psc.json.rm_error @{'completion' = $_ }) -f Red
            }
        }
    }
    function _Update {
        if ($arg.Length -eq 1) {
            Write-Host (_psc_replace $_psc.json.check_update) -f Yellow
            Read-Host (_psc_replace $_psc.json.confirm)
            $res = _psc_check_update
            if ($res) {
                Write-Host $_psc.json.update_can -f Yellow
                Write-Host $res -f Green
            }
            else {
                Write-Host $_psc.json.update_no -f Green
            }
        }
        else {
            $list = $arg[1..($arg.Length - 1)]
            foreach ($_ in $list) {
                if ($_ -in $_psc.installed.BaseName) {
                    _psc_add_completion $_ $true $true
                }
                else {
                    Write-Host (_psc_replace $_psc.json.update_error @{'completion' = $_ }) -f Red
                }
            }
        }
    }

    function _Search {
        if ($arg.Length -lt 2) {
            param_error 'min' 'scoop' ''
            return
        }
        elseif ($arg.Length -gt 2) {
            param_error 'max' 'scoop' ''
            return
        }
        Write-Host ($_psc.json.search + $arg[1] + ' ...') -f Yellow
        _psc_download_list
        foreach ( $_ in $_psc.list) {
            if ( $_ -like ('*' + $arg[1] + '*')) {
                Write-Host $_ -f green
            }
        }
    }

    function _Which {
        if ($arg.Length -lt 2) {
            param_error 'min'
            return
        }
        $list = $arg[1..($arg.Length - 1)]
        foreach ($_ in $list) {
            if ($_ -in $_psc.installed.BaseName) {
                echo ($_psc.completions + '\' + $_)
            }
            else {
                Write-Host (_psc_replace $_psc.json.which_error @{'completion' = $_ }) -f Red
            }
        }
    }

    function _alias {
        $cmds = @('add', 'rm', 'list', 'reset')
        if ($arg.Length -eq 1) {
            param_error 'min' '<list|add|rm|reset> [Compleiton...]' ((_templete $arg[0] 'add' 'scoop'  'volta' '...') + (_templete $arg[0] 'rm' 'scoop'  'volta' '...') + (_templete $arg[0] 'list') + (_templete $arg 'reset'))
            return
        }
        if ($arg[1] -notin $cmds) {
            Write-Host (_psc_replace $_psc.json.param_error  @{'error_cmd' = $arg[1]; 'cmds' = '(' + ($cmds -join ',') + ')' }) -f Red
            return
        }
        function check_add_cm($value, $num, $num2) {
            if ($arg[1] -eq $value) {
                function _do($v) {
                    param_error $v ($value + ' <Completion> <Alias>') (_templete $arg[0] $value 'scoop' 'sco')
                }
                if ($arg.Length -lt $num) {
                    _do 'min'
                    return $true
                }
                elseif ($arg.Length -gt $num2) {
                    _do 'max'
                    return $true
                }
            }
            return $false
        }
        if (check_add_cm 'add' 4 4) { return }
        if (check_add_cm 'rm' 3 999) { return }

        if ($arg.Length -gt 2) {
            if ($arg[1] -eq 'list') {
                param_error 'max' 'list' ''
                return
            }
            elseif ($arg[1] -eq 'reset') {
                param_error 'max' 'reset' ''
                return
            }
        }
        $list = Get-ChildItem -Path ($_psc.root_dir + '\completions') -Filter ".alias" -Recurse
        if ($arg[1] -eq 'list') {
            $data = New-Object System.Collections.ArrayList
            foreach ($_ in $list) {
                $cmd_old = Split-Path (Split-Path $_.FullName -Parent) -Leaf
                $data += [PSCustomObject]@{
                    Command = $cmd_old
                    Alias   = _psc_get_content $_.FullName
                }
            }
            $data | Format-Table -AutoSize -Wrap
            Write-Host (_psc_replace $_psc.json.alias_tip) -f Yellow
            return
        }
        elseif ($arg[1] -eq 'add') {
            if ($arg[2] -in $_psc.installed.baseName) {
                echo $arg[3] > ($_psc.completions + '\' + $arg[2] + '\.alias')
                Write-Host (_psc_replace $_psc.json.alias_add  @{
                        'old' = $arg[2]
                        'new' = $arg[3]
                    }) -f Green
            }
            else {
                Write-Host (_psc_replace $_psc.json.alias_error  @{'completion' = $arg[2] }) -f Red
            }
        }
        elseif ($arg[1] -eq 'rm') {
            $rm_list = $arg[2..($arg.Length - 1)]
            $info = ''
            foreach ($_ in $list) {
                $cmd = Split-Path (Split-Path $_.FullName -Parent) -Leaf
                $alias = _psc_get_content $_.FullName
                if ($alias -in $rm_list) {
                    $info += $alias + '(' + $cmd + ')' + ' '
                    rm $_.FullName -Force
                }
            }
            if ($info) {
                Write-Host (_psc_replace ($_psc.json.alias_del)  @{
                        'list' = $info
                    }) -f Green
            }
            else {
                Write-Host (_psc_replace ($_psc.json.alias_rm_error)  @{
                        'list' = '(' + ($rm_list -split ',') + ')'
                    }) -f Red
            }

        }
        else {
            Write-Host (_psc_replace $_psc.json.reset_confirm) -f Yellow
            Read-Host (_psc_replace $_psc.json.confirm)
            $info = ($_psc.json.alias_del).Replace('${{list}}', '')
            foreach ($_ in $list) {
                $cmd_old = Split-Path (Split-Path $_.FullName -Parent) -Leaf
                $alias = _psc_get_content $_.FullName
                $info += $alias + '(' + $cmd_old + ')' + ' '
                rm $_.FullName -Force
            }
            if ($list) {
                Write-Host (_psc_replace $_psc.json.alias_reset  @{
                        'list' = "`n" + $info + "`n"
                    }) -f Green
            }
        }
    }

    function _Config {
        function _do($value) {
            param_error $value 'language en-US' (_templete $arg[0] 'root_cmd' 'p')
        }
        if ($arg.Length -lt 2) {
            _do 'min'
            return
        }
        elseif ($arg.Length -gt 3) {
            _do 'max'
            return
        }
        if ($arg.Length -eq 2) {
            if ($arg[1] -in $_psc.config.Keys) {
                echo ($_psc.config[$arg[1]])
            }
            else {
                Write-Host (_psc_replace $_psc.json.config_error @{'config' = $arg[1] }) -f Red
            }
        }
        else {
            if ($arg[1] -in $_psc.config.Keys) {
                if ($arg[1] -eq 'root_cmd') {
                    echo $arg[2] > ($_psc.completions + '\PSCompletions\.alias')
                }
                _psc_set_config $arg[1] $arg[2]
                Write-Host (_psc_replace $_psc.json.config_completed  @{
                        'config' = $arg[1]
                        'value'  = $arg[2]
                    }) -f Green
            }
            else {
                Write-Host (_psc_replace $_psc.json.config_error @{'config' = $arg[1] }) -f Red
            }
        }
    }

    function _Help {
        Write-Host (_psc_replace $_psc.json.description) -f DarkCyan
    }

    switch ($arg[0]) {
        'list' {
            _list
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
        }
        'which' {
            _Which
        }
        'alias' {
            _alias
        }
        'config' {
            _Config
        }
        default {
            if ($arg.Length -eq 1) {
                Write-Host (_psc_replace $_psc.json.cmd_error @{
                        'sub_cmd' = $arg[0]
                    }) -f Red
            }
            else { _Help }
        }
    }
    psc_init > $null
}
