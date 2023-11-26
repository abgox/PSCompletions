using namespace System.Management.Automation
using namespace System.Management.Automation.Language
Register-ArgumentCompleter -CommandName $_psc.comp_cmd.wt -ScriptBlock {
    param($wordToComplete, $commandAst)

    #region : Store
    $root_cmd = $_psc.comp_cmd.wt
    $_i = 9999

    if ($_psc.jobs.State -eq 'Completed') {
        $_psc.comp_data = Receive-Job $_psc.jobs
    }
    try { Remove-Job $_psc.jobs }catch {}

    if (!$_psc.comp_data.$root_cmd) {
        $_psc.comp_data.$root_cmd = @{}

        $json = Get-Content -Raw -Path  ($PSScriptRoot + '\json\' + $_psc.lang + '.json') -Encoding UTF8 | ConvertFrom-Json

        $_psc.comp_data.$($root_cmd + '_info') = @{
            core_info = $json.wt_core_info
            exclude   = @('wt_core_info')
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

    $completions = $_psc.comp_data.$root_cmd.Clone()
    $_info = $_psc.comp_data.$($root_cmd + '_info').core_info
    $need_skip = @('-p', '-d', '-h', '-v')
    #endregion

    #region : Special
    try {
        $terminal_config = Get-Content "$env:userprofile\Appdata\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json" -ErrorAction Stop | ConvertFrom-Json
        $terminal_config.profiles.list.name | ForEach-Object {
            $name = $_.Replace(' ', '_')
            $completions[$root_cmd + ' -p ' + $name ] = @(('"' + $_ + '"'), ($_info.p + ' -- ' + $_), $_i++)
        }
    }
    catch {}
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
            try { $_psc.comp_data.$cmd.$($cmd + ' ' + $_)[-1] }catch { 99999 }
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
