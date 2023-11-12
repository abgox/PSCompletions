using namespace System.Management.Automation
using namespace System.Management.Automation.Language
Register-ArgumentCompleter -CommandName $_psc.comp_cmd.choco -ScriptBlock {
    param($wordToComplete, $commandAst)

    #region : Store
    $root_cmd = $_psc.comp_cmd.choco
    $_i = 9999
    if (!$_psc.comp_data.$root_cmd) {
        $_psc.comp_data.$root_cmd = [ordered]@{}

        $_psc.comp_data.$($root_cmd + '_info') = @{
            core_info = $json.choco_core_info
            exclude   = @('choco_core_info')
            num       = -1
        }

        $json = Get-Content -Raw -Path  ($PSScriptRoot + '\json\' + $_psc.lang + '.json') -Encoding UTF8 | ConvertFrom-Json

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

    # $_info = $_psc.comp_data.$($root_cmd + '_info').core_info
    #endregion

    #region : Running
    $input_arr = $commandAst.CommandElements
    $space_tab = if (!$wordToComplete.length) { 1 }else { 0 }

    $max_len = 0
    $display_count = 0
    $cmd_line = [System.Console]::WindowHeight - 5
    $filter_list = $completions.Keys | Where-Object {
        $cmd = $_ -split ' '
        $cmd.Count -eq ($input_arr.Count + $space_tab) -and ($cmd -join ' ') -like (($input_arr -join ' ') + '*')
    }

    $filter_list = $filter_list | Sort-Object { $_psc.comp_data.$root_cmd.$_[-1] }

    $filter_list | ForEach-Object {
        # $completions[$_][0] = $completions[$_][0].Replace('^up', ' ')
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

        $cmd = $_psc.comp_cmd.choco

        try {
            $history = [array](Get-Content (Get-PSReadLineOption).HistorySavePath | Where-Object { ($_ -split '\s+')[0] -eq $cmd })
            $history = $history[-1] -split ' '
            while ($history.Count -gt 1) {
                try {
                    $_psc.comp_data.$cmd.$($history -join ' ')[-1] = $_psc.comp_data.$($cmd + '_info').num--
                }
                catch {}
                $history = $history[0..($history.Count - 2)]
            }
        }
        catch {}

        $json_order = (Get-Content -Raw -Path  ($PSScriptRoot + '\json\' + $_psc.lang + '.json') -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties.Name | Where-Object { $_ -notin $_psc.comp_data.$($cmd + '_info').exclude }  | Sort-Object {
            $_psc.comp_data.$cmd.$($cmd + ' ' + $_)[-1]
        }
        $path_order = $PSScriptRoot + '\order.json'
        $order_old = (Get-Content -Raw -Path $path_order | ConvertFrom-Json).PSObject.Properties.Name

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
