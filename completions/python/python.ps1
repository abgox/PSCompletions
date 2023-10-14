using namespace System.Management.Automation
using namespace System.Management.Automation.Language
Register-ArgumentCompleter -CommandName $_psc.comp_cmd.python -ScriptBlock {
    param($wordToComplete, $commandAst)

    $root_cmd = $_psc.comp_cmd.python

    #region : Store
    $json = _psc_parse_json_with_LRU $PSScriptRoot
    $completions = [ordered]@{}
    _psc_generate_order $PSScriptRoot | ForEach-Object {
        $completions[$root_cmd + ' ' + $_] = @($_, $json.$_)
    }
    #endregion

    #region : Carry out
    $_input = $commandAst.CommandElements
    $_input_str = $_input -join ' '
    $input_tab = if (!$wordToComplete.length) { 1 }else { 0 }
    if ($_input[-1] -match "^[./\\]*$") { return }
    if ($input_tab) {
        $completions.Keys | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            $display = $completions[$_][0].Replace('^up', ' ')
            [CompletionResult]::new($display, $display, 'ParameterValue', (_psc_replace $completions[$_][1]))
        }
    }
    else {
        $completions.Keys | Where-Object { $commandElements_str -notlike "*$_*" } | ForEach-Object {
            $display = $completions[$_][0].Replace('^up', ' ')
            [CompletionResult]::new($display, $display, 'ParameterValue', (_psc_replace $completions[$_][1]))
        }
    }
    #endregion

    #region Reorder completion
    $history = try { (Get-History)[-1].CommandLine }catch { '' }
    _psc_reorder_tab $history $PSScriptRoot
    #endregion
}
