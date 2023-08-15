using namespace System.Globalization
using namespace System.Management.Automation
using namespace System.Management.Automation.Language
Register-ArgumentCompleter -CommandName (_psc_get_cmd $PSScriptRoot 'nvm') -ScriptBlock {
    param($wordToComplete, $commandAst)

    $completions = [System.Collections.Specialized.OrderedDictionary]::new()

    #region : Parse json data
    $json_file_name = $PSScriptRoot + '\json\' + $_psc.lang + '.json'
    $jsonContent = (Get-Content -Raw -Path  $json_file_name -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties
    #endregion

    #region : Store all tab-completion
    foreach ($_ in $jsonContent) {
        $subCmd = $_.Name.substring($_.Name.lastIndexOf(' ') + 1)
        $completions[(_psc_get_cmd $PSScriptRoot 'nvm') + ' ' + $_.Name] = [CompletionResult]::new($subcmd, $subcmd, 'ParameterValue', $_.Value)
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
    #endregion
}
