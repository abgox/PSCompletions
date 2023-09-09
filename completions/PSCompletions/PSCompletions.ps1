using namespace System.Globalization
using namespace System.Management.Automation
using namespace System.Management.Automation.Language
Register-ArgumentCompleter -CommandName $_psc.comp_cmd.PSCompletions -ScriptBlock {
    param($wordToComplete, $commandAst)

    $root_cmd = $_psc.comp_cmd.PSCompletions

    #region : Parse json data
    $json = Get-Content -Raw -Path  ($PSScriptRoot + '\json\' + $_psc.lang + '.json') -Encoding UTF8 | ConvertFrom-Json
    $_json = $json.PSObject.Properties
    # #endregion

    #region : Store
    $completions = [ordered]@{}
    foreach ($_ in $_json) {
        if ($_.Name -ne 'PSCompletions_core_info') {
            $last_cmd = $_.Name.substring($_.Name.lastIndexOf(' ') + 1)
            $completions[$root_cmd + ' ' + $_.Name] = @($last_cmd, $_.Value)
        }
    }
    #endregion

    #region Special point
    foreach ($_ in $_psc.list) {
        if ($_ -notin $_psc.comp_cmd.keys) {
            $tip = _psc_replace $_psc.json.add
            $completions[ $root_cmd + ' add ' + $_] = @($_, $tip)
        }
    }
    if ($_psc.update) {
        foreach ($_ in $_psc.update) {
            $tip = _psc_replace $_psc.json.update
            $completions[ $root_cmd + ' update ' + $_] = @($_, $tip)
        }
    }
    foreach ($_ in $_psc.comp_cmd.keys) {
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
    foreach ($_ in @('language', 'root_cmd', 'github', 'gitee', 'update')) {
        $tip = _psc_replace $json.('config ' + $_)
        $completions[$root_cmd + ' config ' + $_] = @($_, $tip)
    }
    #endregion

    #region : Carry out
    $_input = $commandAst.CommandElements
    $limit_value = 0
    $limit_line = 0
    $display_count = 0
    $cmd_line = [System.Console]::WindowHeight - 4
    $input_tab = if ($wordToComplete.length) { $true }else { $false }
    $filter_list = $completions.Keys | Where-Object {
        $cmd = $_ -split '\s+'
        $temp = $cmd[0..($_input.Count - 1)]
        if ($input_tab) {
            $cmd.Count -eq $_input.Count -and $temp -join ' ' -like ($_input -join ' ') + '*'
        }
        else {
            $cmd.Count -eq ($_input.Count + 1) -and $temp -join ' ' -eq $_input
        }
    }

    $filter_list | ForEach-Object {
        $len = $completions[$_][0].Length
        if ($len -ge $limit_value) { $limit_value = $len }
        $line = ($completions[$_][1] -split "`n").Count
        if ($line -ge $limit_line) { $limit_line = $line }
    }
    $comp_count = ($cmd_line - $limit_line ) * [math]::Floor([System.Console]::WindowWidth / ($limit_value + 2))

    if ($comp_count -le [math]::Floor($filter_list.Count * 2 / 3)) {
        $comp_count = $cmd_line * [math]::Floor([System.Console]::WindowWidth / ($limit_value + 2))
    }
    $filter_list | ForEach-Object {
        if ($comp_count -gt $display_count) {
            $display_count++;
            [CompletionResult]::new($completions[$_][0], $completions[$_][0], 'ParameterValue', (_psc_replace $completions[$_][1]))
        }
        else {
            [CompletionResult]::new(" ", "...", 'ParameterValue', "...")
            return
        }
    }
    if ($display_count -eq 1) { echo ' ' }
    #endregion

    #region Reorder completion
    $history = try { (Get-History)[-1].CommandLine }catch { '' }
    _psc_reorder_tab $history $PSScriptRoot
    #endregion
}
