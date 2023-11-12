using namespace System.Management.Automation
using namespace System.Management.Automation.Language
Register-ArgumentCompleter -CommandName $_psc.comp_cmd.chfs -ScriptBlock {
    param($wordToComplete, $commandAst)

    #region : Store
    $root_cmd = $_psc.comp_cmd.chfs
    $_i = 9999
    if (!$_psc.comp_data.$root_cmd) {
        $_psc.comp_data.$root_cmd = [ordered]@{}
        $json = Get-Content -Raw -Path  ($PSScriptRoot + '\json\' + $_psc.lang + '.json') -Encoding UTF8 | ConvertFrom-Json

        $_psc.comp_data.$($root_cmd + '_info') = @{
            # core_info = $json.chfs_core_info
            exclude = @('chfs_core_info')
            num     = -1
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

    $completions = $_psc.comp_data.$root_cmd
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


    $input_arr = $input_arr | Where-Object { $_ -notlike '-*' }

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
    $timer = New-Object Timers.Timer
    $timer.AutoReset = $false
    $timerAction = {
        # LRU
        if ($_psc.comp_data.Count -gt $_psc.config.LRU * 2) {
            $_psc.comp_data.RemoveAt(0)
            $_psc.comp_data.RemoveAt(0)
        }

        $cmd = $_psc.comp_cmd.chfs

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
