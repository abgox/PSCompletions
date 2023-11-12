using namespace System.Management.Automation
using namespace System.Management.Automation.Language
Register-ArgumentCompleter -CommandName $_psc.comp_cmd.scoop -ScriptBlock {
    param($wordToComplete, $commandAst)

    #region : Store
    $root_cmd = $_psc.comp_cmd.scoop
    $_i = 9999
    if (!$_psc.comp_data.$root_cmd) {
        $_psc.comp_data.$root_cmd = [ordered]@{}
        $json = Get-Content -Raw -Path  ($PSScriptRoot + '\json\' + $_psc.lang + '.json') -Encoding UTF8 | ConvertFrom-Json

        $_psc.comp_data.$($root_cmd + '_info') = @{
            core_info = $json.scoop_core_info
            exclude   = @('scoop_core_info')
            num       = -1
        }

        $order = $_psc.fn_get_order($PSScriptRoot, $_psc.comp_data.$($root_cmd + '_info').exclude)

        $json.PSObject.Properties.Name | Where-Object {
            $_ -notin $_psc.comp_data.$($root_cmd + '_info').exclude
        } | ForEach-Object {
            $cmd = $_ -split ' '
            $_o = if ($order.$_) { $order.$_ }else { $_i++ }
            $_psc.comp_data.$root_cmd[$root_cmd + ' ' + $_] = @($cmd[-1], $json.$_, $_o)

            $_psc.comp_data.$root_cmd[$root_cmd + ' help ' + $cmd[0] ] = @($cmd[0], ($json.scoop_core_info.help + ' --- ' + $cmd[0]), $_o)

        }
    }

    $completions = $_psc.comp_data.$root_cmd
    $_info = $_psc.comp_data.$($root_cmd + '_info').core_info
    $need_skip = @('-a', '-v', '--version')
    #endregion

    #region : Special
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
        $completions[$root_cmd + ' bucket rm ' + $_.Name] = @($_.Name, ('Remove bucket --- ' + $_.Name), $_i++)
    }

    function return_str($str) {
        return ($symbol + $str + ' app --- ' + $_.Name + "`n" + $_.FullName)
    }
    Get-ChildItem "$scoop_path\apps" 2>$null | ForEach-Object {
        function _do($cmd, $tip) {

        }
        $completions[$root_cmd + ' ' + 'uninstall' + ' ' + $_.Name] = @($_.Name, (return_str 'Uninstall'), $_i++)
        $completions[$root_cmd + ' ' + 'update' + ' ' + $_.Name] = @($_.Name, (return_str 'Update'), $_i++)
        $completions[$root_cmd + ' ' + 'cleanup' + ' ' + $_.Name] = @($_.Name, (return_str 'Cleanup'), $_i++)
        $completions[$root_cmd + ' ' + 'hold' + ' ' + $_.Name] = @($_.Name, (return_str 'Hold'), $_i++)
        $completions[$root_cmd + ' ' + 'unhold' + ' ' + $_.Name] = @($_.Name, (return_str 'Unhold'), $_i++)
        $completions[$root_cmd + ' ' + 'prefix' + ' ' + $_.Name] = @($_.Name, $_.FullName, $_i++)
    }
    Get-ChildItem "$scoop_global_path\apps" 2>$null | ForEach-Object {
        function _do($cmd, $tip) {
            $cmd = $root_cmd + ' ' + $cmd + ' ' + $_.Name
            if ($completions[$cmd]) {
                $completions[$cmd] = @($_.Name, ($completions[$cmd][1] + "`n" + $_.FullName))
            }
            else {
                $completions[$cmd] = @($_.Name, $tip)
            }
        }
        _do 'uninstall' (return_str 'Uninstall')
        _do 'update' (return_str 'Update')
        _do 'cleanup' (return_str 'Cleanup')
        _do 'hold' (return_str 'Hold')
        _do 'unhold' (return_str 'Unhold')
        _do 'prefix' $_.FullName
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

    #region : Back
    $timer = New-Object Timers.Timer
    $timer.AutoReset = $false
    $timerAction = {
        # LRU
        if ($_psc.comp_data.Count -gt [int]$_psc.config.LRU * 2) {
            $_psc.comp_data.RemoveAt(0)
            $_psc.comp_data.RemoveAt(0)
        }

        $cmd = $_psc.comp_cmd.scoop

        try {
            $history = [array](Get-Content (Get-PSReadLineOption).HistorySavePath | Where-Object { ($_ -split '\s+')[0] -eq $cmd })
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

        $json_order = (Get-Content -Raw -Path ($PSScriptRoot + '\json\' + $_psc.lang + '.json') -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties.Name | Where-Object { $_ -notin $_psc.comp_data.$($cmd + '_info').exclude }  | Sort-Object {
            $_psc.comp_data.$cmd.$($cmd + ' ' + $_)[-1]
        }
        $path_order = $PSScriptRoot + '\order.json'
        $order_old = (Get-Content -Raw -Path ($path_order) | ConvertFrom-Json).PSObject.Properties.Name

        if (($json_order -join ' ') -ne ($order_old -join ' ')) {
            $i = 1
            $order = [ordered]@{}
            $json_order | ForEach-Object {
                $order.$_ = $i++
            }
            $order | ConvertTo-Json | Out-File $path_order -Force
        }
    }

    $null = Register-ObjectEvent -InputObject $timer -EventName Elapsed -Action $timerAction

    $timer.Start()
    #endregion
}
