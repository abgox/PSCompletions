Register-ArgumentCompleter -CommandName $PSCompletions.comp_cmd.volta -ScriptBlock {
    param($word_to_complete, $command_ast, $cursor_position)

    #region : Store
    $root_cmd = $PSCompletions.comp_cmd.volta

    $PSCompletions.fn_cache($PSScriptRoot)

    $completions = $PSCompletions.comp_data.$root_cmd.Clone()

    $_info = $PSCompletions.comp_data.$($root_cmd + '_info').core_info

    $need_skip = @('--format', '-v','--node','--npm','--yarn','--env')
    #endregion

    #region : Running
    $orgin_input = ($command_ast.CommandElements -join ' ') -split ' '
    $input_arr = $orgin_input
    $space_tab = if (!$word_to_complete.length) { 1 }else { 0 }

    $flag = $input_arr[-1] -notin $need_skip -and $input_arr[-1] -like '-*'

    if ($space_tab) { $complete = ' ' }
    elseif ($flag) {
        $space_tab++
        $complete = ' ' + $word_to_complete
    }

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

    $filter_list = $completions.Keys | Where-Object {
        $cmd = $_ -split ' '
        $cmd[-1] -notin $orgin_input -and $cmd.Count -eq ($input_arr.Count + $space_tab) -and ($cmd -join ' ') -like ($input_arr -join ' ') + $complete + '*'
    } | Sort-Object { $completions.$_[-1] }

    function complete_by_old {
        $max_len = 0
        $display_count = 0
        $cmd_line = [System.Console]::WindowHeight - 5

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
                [CompletionResult]::new($item, $item, 'ParameterValue', ($PSCompletions.fn_replace($completions[$_][1])))
            }
            else {
                [CompletionResult]::new(' ', '...', 'ParameterValue', $PSCompletions.json.comp_hide)
                return
            }
        }
        if ($display_count -eq 1) { ' ' }
    }
    if ($PSCompletions.ui.show -and $PSVersionTable.Platform -ne 'Unix') {
        $PSCompletions.ui.show()
    }
    else { complete_by_old }

    $PSCompletions.fn_order_job($PSScriptRoot, $root_cmd)
    #endregion
}
