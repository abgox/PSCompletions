using namespace System.Management.Automation
using namespace System.Management.Automation.Language
Register-ArgumentCompleter -CommandName $_psc.comp_cmd.chfs -ScriptBlock {
    param($wordToComplete, $commandAst)

    _psc_reorder_tab $PSScriptRoot

    #region : Store
    $root_cmd = $_psc.comp_cmd.chfs
    $json = _psc_parse_json_with_LRU $PSScriptRoot
    $completions = [ordered]@{}
    _psc_generate_order $PSScriptRoot | ForEach-Object {
        $completions[$root_cmd + ' ' + $_] = @($_, $json.$_)
    }
    #endregion

    #region : Running
    $_input = $commandAst.CommandElements
    $_input_str = $_input -join ' '
    $input_tab = if (!$wordToComplete.length) { 1 }else { 0 }
    if ($_input[-1] -match "^[./\\]*$") { return }
    if ($input_tab) {
        $completions.Keys | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            $item = $completions[$_][0]
            [CompletionResult]::new($item, $item, 'ParameterValue', (_psc_replace $completions[$_][1]))
        }
    }
    else {
        $completions.Keys | Where-Object { $commandElements_str -notlike "*$_*" } | ForEach-Object {
            $item = $completions[$_][0]
            [CompletionResult]::new($item, $item, 'ParameterValue', (_psc_replace $completions[$_][1]))
        }
    }
    #endregion
}
