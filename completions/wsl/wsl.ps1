using namespace System.Management.Automation
using namespace System.Management.Automation.Language
Register-ArgumentCompleter -CommandName $_psc.comp_cmd.wsl -ScriptBlock {
    param($wordToComplete, $commandAst)

    #region : Store
    $root_cmd = $_psc.comp_cmd.wsl

    $_psc.fn_cache($PSScriptRoot)

    $completions = $_psc.comp_data.$root_cmd.Clone()

    $_info = $_psc.comp_data.$($root_cmd + '_info').core_info

    $need_skip = @(
        '-u', '--user'
        '-d', '--distribution',
        '-s', '--set-default',
        '-t', '--terminate',
        '--unregister', '--export', '--import',
        '--shell-type', '--install',
        '--mount', '--unmount', '--update', '-l', '--list'
    )
    #endregion

    #region : Special
    $_i = 99999
    function clean_nul($data) {
        $res = [System.Collections.Generic.List[byte]]::new()
        [System.Text.Encoding]::UTF8.GetBytes($data) | ForEach-Object {
            # Remove NUL(0x00) characters from binary data
            if ($_ -ne 0x00) { $res.add($_) }
        }
        return [System.Text.Encoding]::UTF8.GetString($res)
    }

    $Distro_list = wsl -l -q | ForEach-Object { clean_nul $_ } | Where-Object { $_ -ne '' }
    $Distro_list | ForEach-Object {
        $Distro = $_
        function _do($cmd, $tip) {
            $completions[$root_cmd + ' ' + $cmd + ' ' + $Distro] = @($Distro, $tip, $_i)
        }
        $temp = $_psc.fn_replace($_info.symbol + $_info.Distro)

        _do '~ -d' $temp
        _do '~ --distribution' $temp
        _do '-d' $temp
        _do '--distribution' $temp
        _do '-s' ($_info.s + $Distro)
        _do '--set-default' ($_info.s + $Distro)
        _do '-t' $_psc.fn_replace($_info.Distro_t)
        _do '--terminate' $_psc.fn_replace($_info.Distro_t)
        _do '--unregister' $_psc.fn_replace($_info.Distro_u)
        _do '--export' $_psc.fn_replace($_info.Distro_e)
        $_i++
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
            else {
                $res += $input_arr[$i]
            }
        }
        return $res
    }

    $_psc.test = $input_arr = format_input $input_arr $need_skip

    $max_len = 0
    $display_count = 0
    $cmd_line = [System.Console]::WindowHeight - 5
    $filter_list = $completions.Keys | Where-Object {
        $cmd = $_ -split ' '
        $cmd.Count -eq ($input_arr.Count + $space_tab) -and ($cmd -join ' ') -like ($input_arr -join ' ') + $complete + '*'
    }

    $filter_list = $filter_list | Sort-Object { $completions.$_[-1] }

    $filter_list | ForEach-Object {
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
