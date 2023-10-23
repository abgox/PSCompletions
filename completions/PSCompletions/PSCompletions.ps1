using namespace System.Management.Automation
using namespace System.Management.Automation.Language
Register-ArgumentCompleter -CommandName $_psc.comp_cmd.PSCompletions -ScriptBlock {
    param($wordToComplete, $commandAst)

    _psc_reorder_tab $PSScriptRoot

    #region : Store
    $root_cmd = $_psc.comp_cmd.PSCompletions
    $json = _psc_parse_json_with_LRU $PSScriptRoot
    $completions = [ordered]@{}
    _psc_generate_order $PSScriptRoot | ForEach-Object {
        $cmd = $_ -split ' '
        $completions[$root_cmd + ' ' + $_] = @($cmd[-1], $json.$_)
    }
    #endregion

    #region : Special
    $_psc.list | ForEach-Object {
        if ($_ -notin $_psc.comp_cmd.keys) {
            $tip = _psc_replace $_psc.json.add
            $completions[ $root_cmd + ' add ' + $_] = @($_, $tip)
        }
    }
    if ($_psc.update) {
        $_psc.update | ForEach-Object {
            $tip = _psc_replace $_psc.json.update
            $completions[ $root_cmd + ' update ' + $_] = @($_, $tip)
        }
    }
    else {
        $completions.Remove($root_cmd + ' update *' )
    }

    $_psc.comp_cmd.keys | ForEach-Object {
        $alias = $_psc.comp_cmd.$_
        $tip_rm = _psc_replace $_psc.json.remove
        if ($_ -ne 'PSCompletions') {
            $completions[$root_cmd + ' rm ' + $_] = @($_, $tip_rm)
        }

        $tip_which = _psc_replace $_psc.json.which
        $completions[$root_cmd + ' which ' + $_] = @($_, $tip_which)

        $tip_alias_add = _psc_replace $_psc.json.alias_add
        $completions[$root_cmd + ' alias add ' + $_] = @($_, $tip_alias_add)

        $default = $_ -eq $alias
        $default_psc = $_ -eq 'PSCompletions' -and $alias -eq 'psc'
        if (!($default -or $default_psc)) {
            $tip_alias_rm = _psc_replace $_psc.json.alias_rm
            $completions[$root_cmd + ' alias rm ' + $alias] = @($alias, $tip_alias_rm)
        }
    }
    @('language', 'root_cmd', 'github', 'gitee', 'update') | ForEach-Object {
        $tip = _psc_replace $json.('config ' + $_)
        $completions[$root_cmd + ' config ' + $_] = @($_, $tip)
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
