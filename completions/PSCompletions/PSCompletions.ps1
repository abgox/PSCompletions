using namespace System.Globalization
using namespace System.Management.Automation
using namespace System.Management.Automation.Language
Register-ArgumentCompleter -CommandName $_psc.root_cmd -ScriptBlock {
    param($wordToComplete, $commandAst)

    $completions = [System.Collections.Specialized.OrderedDictionary]::new()

    #region : Parse json data
    $json_completion = $PSScriptRoot + '\json\' + $_psc.lang + '.json'
    $json = Get-Content -Raw -Path  $json_completion -Encoding UTF8 | ConvertFrom-Json
    $json_content = $json.PSObject.Properties
    # #endregion
    #region : Store all tab-completion
    foreach ($_ in $json_content) {
        $subCmd = $_.Name.substring($_.Name.lastIndexOf(' ') + 1)
        if ($_.Name -ne 'PSCompletions_core_info') {
            $completions[ $_psc.root_cmd + ' ' + $_.Name] = [CompletionResult]::new($subcmd, $subcmd, 'ParameterValue', (_psc_replace $_.value))
        }
    }
    #endregion

    #region Special point
    foreach ($_ in $_psc.list) {
        if ($_psc.installed.BaseName -inotcontains $_ ) {
            $completions[ $_psc.root_cmd + ' add ' + $_] = [CompletionResult]::new($_, $_, 'ParameterValue', (_psc_replace $_psc.json.add) )
        }
    }
    if ($_psc.update) {
        foreach ($_ in $_psc.update) {
            $completions[ $_psc.root_cmd + ' update ' + $_] = [CompletionResult]::new($_, $_, 'ParameterValue', (_psc_replace $_psc.json.update))
        }
    }
    foreach ($_ in $_psc.installed.BaseName) {
        $completions[$_psc.root_cmd + ' rm ' + $_] = [CompletionResult]::new($_, $_, 'ParameterValue', (_psc_replace $_psc.json.rm))
        $completions[$_psc.root_cmd + ' which ' + $_] = [CompletionResult]::new($_, $_, 'ParameterValue', (_psc_replace $_psc.json.which))
    }
    foreach ($_ in @('root_cmd', 'github', 'gitee', 'language', 'update')) {
        $completions[$_psc.root_cmd + ' config ' + $_] = [CompletionResult]::new($_, $_, 'ParameterValue', (_psc_replace ($_psc.json.config + $json.('config ' + $_))))
    }
    #endregion


    #region : Carry out
    $commandElements = $commandAst.CommandElements
    function completion($num) {
        # Space($num=0)/input($num=-1) and then tab
        $completions.Keys | Where-Object { $_ -like "$commandElements*" } | ForEach-Object {
            $input_space_count = ($commandElements -split ' ').Count - 1
            $cmd_space_count = ($_ -split ' ').Count - 1
            if ($input_space_count -eq $cmd_space_count + $num) { $completions[$_] }
        }
    }
    completion $(if ($wordToComplete.length) { 0 }else { -1 })
}
