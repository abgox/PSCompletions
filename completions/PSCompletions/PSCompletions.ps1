using namespace System.Globalization
using namespace System.Management.Automation
using namespace System.Management.Automation.Language
Register-ArgumentCompleter -CommandName $_psc.comp_cmd.PSCompletions -ScriptBlock {
    param($wordToComplete, $commandAst)

    $completions = [ordered]@{}
    $root_cmd = $_psc.comp_cmd.PSCompletions

    #region : Parse json data
    $json = Get-Content -Raw -Path  ($PSScriptRoot + '\json\' + $_psc.lang + '.json') -Encoding UTF8 | ConvertFrom-Json
    $_json = $json.PSObject.Properties
    # #endregion

    #region : Store
    foreach ($_ in $_json) {
        if ($_.Name -ne 'PSCompletions_core_info') {
            $subCmd = $_.Name.substring($_.Name.lastIndexOf(' ') + 1)
            $completions[ $root_cmd + ' ' + $_.Name] = @([CompletionResult]::new($subcmd, $subcmd, 'ParameterValue', (_psc_replace $_.value)), $subCmd.length, ($_.Value -split "`n").Count)
        }
    }
    #endregion

    #region Special point
    foreach ($_ in $_psc.list) {
        if ($_ -notin $_psc.comp_cmd.keys) {
            $tip = _psc_replace $_psc.json.add
            $completions[ $root_cmd + ' add ' + $_] = @([CompletionResult]::new($_, $_, 'ParameterValue', $tip), $_.Length, ($tip -split "`n").Count)
        }
    }
    if ($_psc.update) {
        foreach ($_ in $_psc.update) {
            $tip = _psc_replace $_psc.json.update
            $completions[ $root_cmd + ' update ' + $_] = @([CompletionResult]::new($_, $_, 'ParameterValue', $tip), $_.Length, ($tip -split "`n").Count)
        }
    }
    foreach ($_ in $_psc.comp_cmd.keys) {
        $alias = $_psc.comp_cmd.$_
        $tip_rm = _psc_replace $_psc.json.remove
        $completions[$root_cmd + ' rm ' + $_] = @([CompletionResult]::new($_, $_, 'ParameterValue', $tip_rm), $_.Length, ($tip_rm -split "`n").Count)

        $tip_which = _psc_replace $_psc.json.which
        $completions[$root_cmd + ' which ' + $_] = @([CompletionResult]::new($_, $_, 'ParameterValue', $tip_which), $_.Length, ($tip_which -split "`n").Count)

        $tip_alias_add = _psc_replace $_psc.json.alias_add
        $completions[$root_cmd + ' alias add ' + $_] = @([CompletionResult]::new($_, $_, 'ParameterValue', $tip_alias_add), $_.Length, ($tip_alias_add -split "`n").Count)

        if (!($_ -eq 'PSCompletions' -and $alias -eq 'psc')) {
            $tip_alias_rm = _psc_replace $_psc.json.alias_rm
            $completions[$root_cmd + ' alias rm ' + $alias] = @([CompletionResult]::new($_, $_, 'ParameterValue', $tip_alias_rm), $_.Length, ($tip_alias_rm -split "`n").Count)
        }
    }
    foreach ($_ in @('language', 'root_cmd', 'github', 'gitee', 'update')) {
        $tip = _psc_replace $json.('config ' + $_)
        $completions[$root_cmd + ' config ' + $_] = @([CompletionResult]::new($_, $_, 'ParameterValue', $tip), $_.Length, ($tip -split "`n").Count)
    }
    #endregion

    #region : Carry out
    $_input = $commandAst.CommandElements
    $cmd_line = [System.Console]::WindowHeight - 4
    $limit_max = @(0, 0)
    $count = 0
    $display_count = 0
    $input_tab = if ($wordToComplete.length) { $true }else { $false }
    $input_count = $_input.Count
    $all = $completions.Keys | Where-Object {
        $cmd = $_ -split '\s+'
        $temp = $cmd[0..($input_count - 1)]
        if ($input_tab) {
            $cmd.Count -eq $input_count -and $temp -join ' ' -like ($_input -join ' ') + '*'
        }
        else {
            $cmd.Count -eq ($input_count + 1) -and ($temp -join ' ') -eq $_input
        }
    } | foreach-Object {
        if ($completions[$_][1] -ge $limit_max[0]) { $limit_max[0] = $completions[$_][1] }
        if ($completions[$_][2] -ge $limit_max[1]) { $limit_max[1] = $completions[$_][2] }
        $count++
        $_
    }
    $comp_count = ($cmd_line - $limit_max[1] ) * [math]::Floor([System.Console]::WindowWidth / ($limit_max[0] + 2))
    if ($comp_count -le [math]::Floor($count * 2 / 3)) {
        $comp_count = $cmd_line * [math]::Floor([System.Console]::WindowWidth / ($limit_max[0] + 2))
    }
    $all | ForEach-Object {
        $display_count++;
        if ($comp_count -gt $display_count) { $completions[$_][0] }
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
