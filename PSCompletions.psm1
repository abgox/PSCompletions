<#
# @Author      : abgox
# @Github      : https://github.com/abgox/PSCompletions
#>

. $PSScriptRoot\core\replace.ps1
function PSCompletions {
    $arg = $args
    function _templete($list) {
        foreach ($_ in $list) {
            $res += ' ' + $_
        }
        return ("`n" + '    ' + $_psc.config.root_cmd + ' ' + $arg[0] + $res)
    }
    function param_error {
        if ($args[0] -eq 'min') {
            $res = $_psc.json.param_min
        }
        else {
            $res = $_psc.json.param_max
        }
        $completion = $args[1]
        $example = $args[2]
        Write-Host (_psc_replace ($res + $_psc.json.example)) -f Red
    }

    function _list {
        if ($arg.Length -gt 1) {
            param_error 'max'
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
            param_error 'min' 'git' (_templete @('git', 'scoop', '...'))
            return
        }
        _psc_download_list
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
            param_error 'min' 'git' (_templete @('git', 'scoop', '...'))
            return
        }
        $list = $arg[1..($arg.Length - 1)]
        foreach ($_ in $list) {
            if ($_ -in $_psc.installed.BaseName) {
                $dir = $PSScriptRoot + '\completions\' + $_
                rmdir $dir -Recurse -Force
                if (!(Test-Path($dir))) {
                    Write-Host (_psc_replace $_psc.json.rm_completed) -f Green
                }
            }
            else {
                Write-Host (_psc_replace $_psc.json.rm_error) -f Red
            }
        }
    }
    function _Update {
        function _do {
            try {
                $res = New-Object System.Collections.ArrayList
            foreach ($_ in $_psc.installed.BaseName) {
                $url = $_psc.url + '/completions/' + $_ + '/.guid'
                $response = Invoke-WebRequest -Uri  $url
                if ($response.StatusCode -eq 200) {
                    $content = ($response.Content).Trim()
                    $guid = (_psc_get_content ($_psc.completions + '\' + $_ + '\.guid')).Trim()
                    if ($guid -ne $content) { $res.Add($_) > $null }
                }
            }
            echo $res > $_psc.update_path
            $_psc.update = _psc_get_content $_psc.update_path
            Write-Host '----------' -f Cyan
            if ($res) {
                Write-Host (_psc_replace $_psc.json.update_can) -f Yellow
                Write-Host (_psc_replace $_psc.update) -f Green
            }
            else {
                Write-Host (_psc_replace $_psc.json.update_no) -f Green
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
                        if ($_ -in $_psc.installed.BaseName) {
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
            param_error 'min' '*' ((_templete @('*n*')) + (_templete @('git')))
            return
        }
        elseif ($arg.Length -gt 2) {
            param_error 'max' '*' ((_templete @('*n*')) + (_templete @('git')))
            return
        }
        Write-Host (_psc_replace ($_psc.json.search + $arg[1] + ' ...')) -f Yellow
        _psc_download_list

        foreach ( $_ in $_psc.list) {
            if ( $_ -like ($arg[1])) {
                Write-Host $_ -f green
            }
        }
    }

    function _Which {
        if ($arg.Length -lt 2) {
            param_error 'min' 'git' (_templete @('git', 'scoop', '...'))
            return
        }
        $list = $arg[1..($arg.Length - 1)]
        foreach ($_ in $list) {
            if ($_ -in $_psc.installed.BaseName) {
                echo ($_psc.completions + '\' + $_)
            }
            else {
                Write-Host (_psc_replace $_psc.json.which_error) -f Red
            }
        }
    }

    function _alias {
        $cmd_list = @('add', 'rm', 'list', 'reset')
        if ($arg.Length -eq 1) {
            param_error 'min' 'add scoop sco' ((_templete @('rm', 'sco')) + (_templete @('list')) + (_templete @( 'reset')))
            return
        }
        if ($arg[1] -notin $cmd_list) {
            Write-Host (_psc_replace $_psc.json.param_error) -f Red
            return
        }

        if ($arg[1] -eq 'add') {
            if ($arg.Length -lt 4) {
                param_error 'min' 'add <completion> <alias>'  (_templete @('add', 'scoop', 'sco'))
                return
            }
            elseif ($arg.Length -gt 4) {
                param_error 'max' 'add <completion> <alias>' (_templete @('add', 'scoop', 'sco'))
                return
            }
        }
        if ($arg[1] -eq 'rm') {
            if ($arg.Length -lt 4) {
                param_error 'min' 'rm <alias...>'  ((_templete @('rm', 'sco'))+ (_templete @('rm', 'sco','...')))
                return
            }
            elseif ($arg.Length -gt 4) {
                param_error 'max' 'rm <alias...>' ((_templete @('rm', 'sco'))+ (_templete @('rm', 'sco','...')))
                return
            }
        }
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
                Write-Host (_psc_replace $_psc.json.alias_add) -f Green
            }
            else {
                Write-Host (_psc_replace $_psc.json.alias_error) -f Red
            }
        }
        elseif ($arg[1] -eq 'rm') {
            $rm_list = $arg[2..($arg.Length - 1)]
            $del_list = @()
            $error_list = @()
            foreach ($_ in $list) {
                $cmd = Split-Path (Split-Path $_.FullName -Parent) -Leaf
                $alias = _psc_get_content $_.FullName
                foreach ($item in $rm_list) {
                    if ($alias -eq $item) {
                        $del_list += $alias + '(' + $cmd + ')' + ' '
                        rm $_.FullName -Force
                    }
                    else {
                        $error_list += $item
                    }
                }
            }
            if ($del_list) {
                Write-Host (_psc_replace $_psc.json.alias_del) -f Green
            }
            if ($error_list) {
                Write-Host (_psc_replace ($_psc.json.alias_rm_error)) -f Red
            }
        }
        else {
            Write-Host (_psc_replace $_psc.json.reset_confirm) -f Yellow
            Read-Host (_psc_replace $_psc.json.confirm)
            $del_list = ''
            foreach ($_ in $list) {
                $cmd_old = Split-Path (Split-Path $_.FullName -Parent) -Leaf
                $alias = _psc_get_content $_.FullName
                $del_list += $alias + '(' + $cmd_old + ')' + ' '
                rm $_.FullName -Force
            }
            _psc_set_config 'root_cmd' 'psc'
            if ($del_list) {
                Write-Host (_psc_replace (_psc_replace $_psc.json.alias_reset)) -f Green
            }
        }
    }

    function _Config {
        function _do($value) {
            param_error $value 'language en-US' (_templete @('root_cmd', 'p'))
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
                if ($arg[1] -eq 'reset') {
                    $module_version = $_psc.version
                    $root_cmd = 'psc'
                    echo $root_cmd > $_psc.alias_path
                    $github = 'https://github.com/abgox/PSCompletions'
                    $gitee = 'https://gitee.com/abgox/PSCompletions'
                    $language = (Get-WinSystemLocale).name
                    $update = 1
                    [environment]::SetEnvironmentvariable('abgox_PSCompletions', ($module_version + ';' + $root_cmd + ';' + $github + ';' + $gitee + ';' + $language + ';' + $update), 'User')
                    return
                }
                Write-Host (_psc_replace $_psc.json.config_error) -f Red
            }
        }
        else {
            if ($arg[1] -in $_psc.config.Keys) {
                if ($arg[1] -eq 'root_cmd') {
                    echo $arg[2] > $_psc.alias_path
                }
                _psc_set_config $arg[1] $arg[2]
                Write-Host (_psc_replace $_psc.json.config_completed) -f Green
            }
            else {
                Write-Host (_psc_replace $_psc.json.config_error) -f Red
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
                Write-Host (_psc_replace $_psc.json.cmd_error) -f Red
            }
            else { _Help }
        }
    }
    psc_init
}
