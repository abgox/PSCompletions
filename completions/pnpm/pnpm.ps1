using namespace System.Management.Automation
using namespace System.Management.Automation.Language
Register-ArgumentCompleter -CommandName $_psc.comp_cmd.pnpm -ScriptBlock {
    param($wordToComplete, $commandAst)

    _psc_reorder_tab $PSScriptRoot

    #region : Store
    $root_cmd = $_psc.comp_cmd.pnpm
    $json = _psc_parse_json_with_LRU $PSScriptRoot
    $completions = [ordered]@{}
    _psc_generate_order $PSScriptRoot | ForEach-Object {
        $cmd = $_ -split ' '
        $completions[$root_cmd + ' ' + $_] = @($cmd[-1], $json.$_)
    }
    #endregion

    #region : Running
    $_input = $commandAst.CommandElements
    $max_len = 0
    $display_count = 0
    $cmd_line = [System.Console]::WindowHeight - 5
    $input_tab = if (!$wordToComplete.length) { 1 }else { 0 }
    $filter_list = $completions.Keys | Where-Object {
        $cmd = $_ -split ' '
        $cmd.Count -eq ($_input.Count + $input_tab) -and ($cmd -join ' ') -like ($_input -join ' ') + '*'
    }
    $filter_list | ForEach-Object {
        $len = $completions[$_][0].Length
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
}
