using namespace System.Management.Automation
using namespace System.Management.Automation.Language
Register-ArgumentCompleter -CommandName $_psc.comp_cmd.wsl -ScriptBlock {
    param($wordToComplete, $commandAst)

    #region : Store
    $root_cmd = $_psc.comp_cmd.wsl
    $_i = 9999
    if (!$_psc.comp_data.$root_cmd) {
        $_psc.comp_data.$root_cmd = [ordered]@{}
        $json = Get-Content -Raw -Path  ($PSScriptRoot + '\json\' + $_psc.lang + '.json') -Encoding UTF8 | ConvertFrom-Json

        $_psc.comp_data.$($root_cmd + '_info') = @{
            core_info = $json.wsl_core_info
            exclude   = @('wsl_core_info')
            num       = -1
        }

        $order = $_psc.fn_get_order($PSScriptRoot, $_psc.comp_data.$($root_cmd + '_info').exclude)

        $json.PSObject.Properties.Name | Where-Object {
            $_ -notin $_psc.comp_data.$($root_cmd + '_info').exclude
        } | ForEach-Object {
            $cmd = $_ -split ' '
            $_o = if ($order.$_) { $order.$_ }else { $_i++ }
            $_psc.comp_data.$root_cmd[$root_cmd + ' ' + $_] = @($cmd[-1], $json.$_, $_o)
        }
    }
    else {
        if ($_psc.jobs.State -eq 'Completed') {
            $_psc.comp_data = Receive-Job $_psc.jobs
        }
        try { Remove-Job $_psc.jobs }catch {}
    }

    $completions = $_psc.comp_data.$root_cmd
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
            $completions[$root_cmd + ' ' + $cmd + ' ' + $Distro] = @($Distro, $tip, $_i++)
        }
        $temp = $_psc.fn_replace($_info.symbol + $_info.Distro)

        $completions[$root_cmd + ' ~ -d ' + $Distro] = @($Distro, $temp, $_i++)
        $completions[$root_cmd + ' ~ --distribution ' + $Distro] = @($Distro, $temp, $_i++)
        $completions[$root_cmd + ' -d ' + $Distro] = @($Distro, $temp, $_i++)
        $completions[$root_cmd + ' --distribution ' + $Distro] = @($Distro, $temp, $_i++)
        $completions[$root_cmd + ' -s ' + $Distro] = @($Distro, ($_info.s + $Distro), $_i++)
        $completions[$root_cmd + ' --set-default ' + $Distro] = @($Distro, ($_info.s + $Distro), $_i++)
        $completions[$root_cmd + ' -t ' + $Distro] = @($Distro, $_psc.fn_replace($_info.Distro_t), $_i++)
        $completions[$root_cmd + ' --terminate ' + $Distro] = @($Distro, $_psc.fn_replace($_info.Distro_t), $_i++)
        $completions[$root_cmd + ' --unregister ' + $Distro] = @($Distro, $_psc.fn_replace($_info.Distro_u), $_i++)
        $completions[$root_cmd + ' --export ' + $Distro] = @($Distro, $_psc.fn_replace($_info.Distro_e), $_i++)
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

    #region : Back
    $_psc.jobs = Start-Job -ScriptBlock {
        param(
            $_psc,
            $cmd,
            $PSScriptRoots,
            $path_history
        )
        # LRU
        if ($_psc.comp_data.Count -gt [int]$_psc.config.LRU * 2) {
            $_psc.comp_data.RemoveAt(0)
            $_psc.comp_data.RemoveAt(0)
        }
        try {
            $history = [array](Get-Content $path_history | Where-Object { ($_ -split '\s+')[0] -eq $cmd })
            $history = $history[-1] -split ' '

            function fn([array]$history) {
                $_i = 0
                $res = @()
                $history | ForEach-Object {
                    if ($_ -like '-*') {
                        $res += $_i
                    }
                    $_i++
                }
                return $res[0]
            }

            $i = fn $history
            if ($i) {
                $prefix = $history[0..($i - 1)] -join ' '
                $history[$i..($history.Count - 1)] | ForEach-Object {
                    try {
                        $_psc.comp_data.$cmd.$($prefix + ' ' + $_)[-1] = $_psc.comp_data.$($cmd + '_info').num--
                    }
                    catch {}
                }
                $base = $prefix -split ' '
            }
            else {
                $base = $history
            }

            while ($base.Count -gt 1) {
                try {
                    $_psc.comp_data.$cmd.$($base -join ' ')[-1] = $_psc.comp_data.$($cmd + '_info').num--
                }
                catch {}
                $base = $base[0..($base.Count - 2)]
            }
        }
        catch {}

        $json_order = (Get-Content -Raw -Path ($PSScriptRoots + '\json\' + $_psc.lang + '.json') -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties.Name | Where-Object { $_ -notin $_psc.comp_data.$($cmd + '_info').exclude }  | Sort-Object {
            $_psc.comp_data.$cmd.$($cmd + ' ' + $_)[-1]
        }
        $path_order = $PSScriptRoots + '\order.json'
        $order_old = (Get-Content -Raw -Path ($path_order) | ConvertFrom-Json).PSObject.Properties.Name

        if (($json_order -join ' ') -ne ($order_old -join ' ')) {
            $i = 1
            $order = [ordered]@{}
            $json_order | ForEach-Object {
                $order.$_ = $i++
            }
            $order | ConvertTo-Json | Out-File $path_order -Force
        }
        return $_psc.comp_data
    }  -ArgumentList $_psc, $root_cmd, $PSScriptRoot, (Get-PSReadLineOption).HistorySavePath
    #endregion
}
