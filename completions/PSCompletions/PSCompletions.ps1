using namespace System.Management.Automation
using namespace System.Management.Automation.Language
Register-ArgumentCompleter -CommandName $_psc.comp_cmd.PSCompletions -ScriptBlock {
    param($wordToComplete, $commandAst)

    #region : Store
    $root_cmd = $_psc.comp_cmd.PSCompletions

    $_psc.fn_cache($PSScriptRoot, @('PSCompletions_core_info'))

    $completions = $_psc.comp_data.$root_cmd.Clone()

    # $_info = $_psc.comp_data.$($root_cmd + '_info').core_info
    #endregion

    #region : Special
    $_i = 99999
    if ($_psc.update) {
        $_psc.list | ForEach-Object {
            if ($_ -notin $_psc.comp_cmd.keys) {
                $tip = $_psc.fn_replace($_psc.json.add)
                $completions[ $root_cmd + ' add ' + $_] = @($_, $tip, $_i)
                $_i++
            }
        }
        $_psc.update | ForEach-Object {
            $tip = $_psc.fn_replace($_psc.json.update)
            $completions[ $root_cmd + ' update ' + $_] = @($_, $tip, $_i)
            $_i++
        }
    }

    $_psc.comp_cmd.keys | ForEach-Object {
        $alias = $_psc.comp_cmd.$_
        $tip_rm = $_psc.fn_replace($_psc.json.remove)
        if ($_ -ne 'PSCompletions') {
            $completions[$root_cmd + ' rm ' + $_] = @($_, $tip_rm, $_i)
        }

        $tip_which = $_psc.fn_replace($_psc.json.which)
        $completions[$root_cmd + ' which ' + $_] = @($_, $tip_which, $_i)

        $tip_alias_add = $_psc.fn_replace($_psc.json.alias_add)
        $completions[$root_cmd + ' alias add ' + $_] = @($_, $tip_alias_add, $_i)

        $default = $_ -eq $alias
        $default_psc = $_ -eq 'PSCompletions' -and $alias -eq 'psc'
        if (!($default -or $default_psc)) {
            $tip_alias_rm = $_psc.fn_replace($_psc.json.alias_rm)
            $completions[$root_cmd + ' alias rm ' + $alias] = @($alias, $tip_alias_rm, $_i)
        }
        $_i++
    }
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
