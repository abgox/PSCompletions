using namespace System.Management.Automation
using namespace System.Management.Automation.Language
Register-ArgumentCompleter -CommandName $_psc.comp_cmd.nrm -ScriptBlock {
    param($wordToComplete, $commandAst)

    #region : Store
    $root_cmd = $_psc.comp_cmd.nrm

    $_psc.fn_cache($PSScriptRoot)

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

    $filter_list = $filter_list | Sort-Object { $completions.$_[-1] }

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

    $_psc.fn_order_job($PSScriptRoot, $root_cmd)
}
