using namespace System.Management.Automation
using namespace System.Management.Automation.Language
Register-ArgumentCompleter -CommandName $_psc.comp_cmd.$template_comp -ScriptBlock {
    param($wordToComplete, $commandAst)

    $root_cmd = $_psc.comp_cmd.$template_comp

    #region : Store
    $json = _psc_parse_json_with_LRU $PSScriptRoot
    $json_info = $json.$template_comp_core_info
    $completions = [ordered]@{}
    _psc_generate_order $PSScriptRoot | ForEach-Object {
        $cmd = $_ -split ' '
        $completions[$root_cmd + ' ' + $_] = @($cmd[-1], $json.$_)
        $completions[$root_cmd + ' help ' + $cmd[0]] = @($cmd[0], ($json_info.help + ' --- ' + $cmd[0]))
    }
    #endregion

    #region : Carry out
    $_input = $commandAst.CommandElements
    $max_len = 0
    $display_count = 0
    $cmd_line = [System.Console]::WindowHeight - 5
    $input_tab = if (!$wordToComplete.length) { 1 }else { 0 }
    $filter_list = $completions.Keys | Where-Object {
        $cmd = $_ -split ' '
        $position = [System.Collections.Generic.List[int]]@()
        for ($i = 0; $i -lt $cmd.Count; $i++) {
            if ($cmd[$i] -like '<*>') { $position.Add($i) }
        }
        $_inputs = [System.Collections.Generic.List[string]]$_input
        $flag = [System.Collections.Generic.List[string]]$cmd
        $position | ForEach-Object {
            if ($_inputs.Count -gt $_) {
                $flag.RemoveAt($_)
                $_inputs.RemoveAt($_)
            }
        }
        $cmd.Count -eq ($_input.Count + $input_tab) -and ($flag -join ' ') -like ($_inputs -join ' ') + '*'
    }
    $filter_list | ForEach-Object {
        $completions[$_][0] = $completions[$_][0].Replace('^up', ' ')
        $len = ($completions[$_][0]).Length
        if ($len -ge $max_len) { $max_len = $len }
    }

    $comp_count = $cmd_line * [math]::Floor([System.Console]::WindowWidth / ($max_len + 2))

    $filter_list | ForEach-Object {
        if ($comp_count -gt $display_count) {
            $display_count++
            $item = $completions[$_][0]
            [CompletionResult]::new($item, $item, 'ParameterValue', (_psc_replace $completions[$_][1]))
        }
        else {
            [CompletionResult]::new(' ', '...', 'ParameterValue', $_psc.json.comp_hide)
            return
        }
    }
    if ($display_count -eq 1) { ' ' }
    #endregion

    _psc_reorder_tab $PSScriptRoot
}
