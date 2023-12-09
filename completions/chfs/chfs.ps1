Register-ArgumentCompleter -CommandName $PSCompletions.comp_cmd.chfs -ScriptBlock {
    param($word_to_complete, $command_ast, $cursor_position)

    #region : Store
    $root_cmd = $PSCompletions.comp_cmd.chfs

    $PSCompletions.fn_cache($PSScriptRoot)

    $completions = $PSCompletions.comp_data.$root_cmd.Clone()
    #endregion

    #region : Running
    $input_arr = $command_ast.CommandElements
    $space_tab = if (!$word_to_complete.length) { 1 }else { 0 }

    $flag = $input_arr[-1] -notin $need_skip -and $input_arr[-1] -like '-*'

    if ($space_tab) { $complete = ' ' }
    elseif ($flag) {
        $space_tab++
        $complete = ' ' + $word_to_complete
    }

    $input_arr = $input_arr | Where-Object { $_ -notlike '-*' }
    $filter_list = $completions.Keys | Where-Object {
        $cmd = $_ -split ' '
        $cmd.Count -eq ($input_arr.Count + $space_tab) -and ($cmd -join ' ') -like ($input_arr -join ' ') + $complete + '*'
    } | Sort-Object { $completions.$_[-1] }

    function complete_by_old {
        $max_len = 0
        $display_count = 0
        $cmd_line = [System.Console]::WindowHeight - 5

        $filter_list | ForEach-Object {
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
