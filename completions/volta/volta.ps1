<#
# @Author      : abgox
# @Github      : https://github.com/abgox/PS-completions
#>

using namespace System.Globalization
using namespace System.Management.Automation
using namespace System.Management.Automation.Language
Register-ArgumentCompleter -CommandName (_psc_get_cmd $PSScriptRoot 'volta') -ScriptBlock {
    param($wordToComplete, $commandAst)

    $completions = [System.Collections.Specialized.OrderedDictionary]::new()

    # language
    $language_list = Get-ChildItem -Path "$PSScriptRoot\json" | ForEach-Object { $_.BaseName }
    # If $tab_completion_language is set, use it.
    if ($tab_completion_language -in $language_list) {
        $language = $tab_completion_language
    }
    else {
        $system_language = (Get-WinSystemLocale).name
        if ($system_language -in $language_list) {
            $language = $system_language
        }
        else {
            $language = 'en-US'
        }
    }

    #region : Parse json data
    $json_file_name = 'C:\Users\abgox\Documents\Powershell\Modules\PSCompletion\core\test\Gitee\raw\main\completions\volta\json\' + $language + '.json'
    $jsonContent = (Get-Content -Raw -Path  $json_file_name -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties
    #endregion

    #region : Store all tab-completion
    foreach ($_ in $jsonContent) {
        $subCmd = $_.Name.substring($_.Name.lastIndexOf(' ') + 1)
        $completions[(_psc_get_cmd $PSScriptRoot 'volta') + ' ' + $_.Name] = [CompletionResult]::new($subcmd, $subcmd, 'ParameterValue', $_.Value)
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
