Register-ArgumentCompleter -CommandName $PSCompletions.comp_cmd.$template_comp -ScriptBlock {
    param($word_to_complete, $command_ast, $cursor_position)

    #region : Store
    $root_cmd = $PSCompletions.comp_cmd.$template_comp

    $PSCompletions.fn_cache($PSScriptRoot)

    $completions = $PSCompletions.comp_data.$root_cmd.Clone()

    $_info = $PSCompletions.comp_data.$($root_cmd + '_info').core_info
    #endregion

    #region : Special
    # $_i = 99999
    #endregion

    #region : Running
    $input_arr = $command_ast.CommandElements
    $space_tab = if (!$word_to_complete.length) { 1 }else { 0 }
    $match = if ($space_tab) { ' *' }else { '*' }

    $filter_list = $completions.Keys | Where-Object {
        $cmd = $_ -split ' '
        # $cmd_str = ($cmd -join ' ') -replace '\?', '\?'
        # $input_str = ($input_arr -join ' ') -replace '\?', '\?'
        $cmd.Count -eq ($input_arr.Count + $space_tab) -and ($cmd -join ' ') -like (($input_arr -join ' ') + $match)
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
        $comp_count = $cmd_line * ([math]::Floor([System.Console]::WindowWidth) / ($max_len + 2))

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

    # $filter_list | ForEach-Object {
    #     $completions[$_][0] = $completions[$_][0].Replace('^up', ' ')
    # }

    if ($PSCompletions.ui.show -and $PSVersionTable.Platform -ne 'Unix') {
        $PSCompletions.ui.show()
    }
    else { complete_by_old }

    $PSCompletions.fn_order_job($PSScriptRoot, $root_cmd)
    #endregion
}
