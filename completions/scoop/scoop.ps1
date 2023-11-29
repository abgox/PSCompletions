using namespace System.Management.Automation
using namespace System.Management.Automation.Language
Register-ArgumentCompleter -CommandName $_psc.comp_cmd.scoop -ScriptBlock {
    param($wordToComplete, $commandAst)

    #region : Store
    $root_cmd = $_psc.comp_cmd.scoop

    $_psc.fn_cache($PSScriptRoot)

    $completions = $_psc.comp_data.$root_cmd.Clone()

    $_info = $_psc.comp_data.$($root_cmd + '_info').core_info

    $need_skip = @('-a', '-v', '--version')
    #endregion

    #region : Special
    $_i = 99999
    $symbol = $json_info.symbol
    if ($env:SCOOP) {
        $scoop_path = $env:SCOOP
    }
    else {
        $path = (Get-Content -Raw "$env:UserProfile\.config\scoop\config.json" | ConvertFrom-Json).root_path
        if ($path) { [environment]::SetEnvironmentvariable('SCOOP', $path, 'User') }
        $scoop_path = $path
    }

    if ($env:SCOOP_GLOBAL) {
        $scoop_global_path = $env:SCOOP_GLOBAL
    }
    else {
        $path = (Get-Content -Raw "$env:UserProfile\.config\scoop\config.json" | ConvertFrom-Json).global_path
        if ($path) { [environment]::SetEnvironmentvariable('SCOOP_GLOBAL', $path, 'User') }
        $scoop_global_path = $path
    }

    Get-ChildItem "$scoop_path\buckets" 2>$null | ForEach-Object {
        $completions[$root_cmd + ' bucket rm ' + $_.Name] = @($_.Name, ('Remove bucket --- ' + $_.Name), $_i)
        $_i++
    }

    function return_str($str) {
        return ($symbol + $str + ' app --- ' + $_.Name + "`n" + $_.FullName)
    }
    function _do($cmd, $tip) {
        $completions[$root_cmd + ' ' + $cmd + ' ' + $_.Name] = @($_.Name, $tip, $_i)
    }

    @("$scoop_path\apps","$scoop_global_path\apps") | ForEach-Object {
        Get-ChildItem $_ 2>$null | ForEach-Object {
            _do 'uninstall'  (return_str 'Uninstall')
            _do 'update' (return_str 'Update')
            _do 'cleanup' (return_str 'Cleanup')
            _do 'hold' (return_str 'Hold')
            _do 'unhold' (return_str 'Unhold')
            _do 'prefix' $_.FullName
            $_i++
        }
    }
    #endregion

    #region : Running
    $input_str = $commandAst.CommandElements -join ' '
    $input_arr = $input_str -split ' '
    $space_tab = if (!$wordToComplete.length) { 1 }else { 0 }

    $flag = $input_arr[-1] -notin $need_skip -and $input_arr[-1] -like '-*'
    if (!$space_tab -and $flag) {
        $space_tab++
        $complete = ' ' + $wordToComplete
    }
    else { $complete = '' }

    function format_input([array]$input_arr, [array]$need_skip = @()) {
        if ($input_arr.Count -eq 1) {
            return $input_arr[0]
        }
        $res = @()
        $skip = 0
        for ($i = 0; $i -lt $input_arr.Count; $i++) {
            if ($i -eq 1 -and $input_arr[$i] -in $need_skip) {
                $res += $input_arr[$i]
                continue
            }
            if ($skip -and ($i -ne $input_arr.Count - 1 -or $input_arr[$i] -notin $need_skip)) {
                if ($input_arr[$i] -notlike '-*') { $skip = 0 }
                continue
            }
            if ($input_arr[$i] -like '-*') {
                if ($input_arr[$i] -in $need_skip -and $i -eq $input_arr.Count - 1) {
                    $res += $input_arr[$i]
                    return $res
                }
                else {
                    $skip = 1
                }
            }
            else { $res += $input_arr[$i] }
        }
        return $res
    }

    $input_arr = format_input $input_arr $need_skip

    $max_len = 0
    $display_count = 0
    $cmd_line = [System.Console]::WindowHeight - 5
    $filter_list = $completions.Keys | Where-Object {
        $cmd = $_ -split ' '
        $cmd.Count -eq ($input_arr.Count + $space_tab) -and ($cmd -join ' ') -like ($input_arr -join ' ') + $complete + '*'
    }

    $filter_list = $filter_list | Sort-Object { $completions.$_[-1] }

    $filter_list | ForEach-Object {
        $completions[$_][0] = $completions[$_][0].Replace('^up', ' ')
        $len = $completions[$_][0].Length
        if ($len -ge $max_len) { $max_len = $len }
    }

    $comp_count = $cmd_line * [math]::Floor([System.Console]::WindowWidth / ($max_len + 2))

    $filter_list | ForEach-Object {
        if ($comp_count -gt $display_count) {
            $display_count++
            $item = $completions[$_][0]
            [CompletionResult]::new($item, $item, 'ParameterValue', ($_psc.fn_replace($completions[$_][1])))
        }
        else {
            [CompletionResult]::new(' ', '...', 'ParameterValue', $_psc.json.comp_hide)
            return
        }
    }
    if ($display_count -eq 1) { ' ' }
    #endregion

    $_psc.fn_order_job($PSScriptRoot, $root_cmd)
}
