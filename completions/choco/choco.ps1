using namespace System.Globalization
using namespace System.Management.Automation
using namespace System.Management.Automation.Language
Register-ArgumentCompleter -CommandName (_psc_get_cmd $PSScriptRoot 'choco') -ScriptBlock {
    param($wordToComplete, $commandAst)

    $completions = [System.Collections.Specialized.OrderedDictionary]::new()
    $root_cmd = (_psc_get_cmd $PSScriptRoot 'choco')

    #region : Parse json data
    $_name = $PSScriptRoot + '\json\' + $_psc.lang + '.json'
    $_json = (Get-Content -Raw -Path  $_name -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties
    #endregion

    #region : Store
    $max_len = 0
    foreach ($_ in $_json) {
        $subCmd = $_.Name.substring($_.Name.lastIndexOf(' ') + 1)
        if ($max_len -lt $subCmd.length) {
            $max_len = $subCmd.length
        }
        $completions[$root_cmd + ' ' + $_.Name] = [CompletionResult]::new($subcmd, $subcmd, 'ParameterValue', (_psc_replace $_.value))
        $completions[$root_cmd + ' help ' + $_.Name] = [CompletionResult]::new($subcmd, $subcmd, 'ParameterValue', '...')

    }
    #endregion

    #region : Carry out
    $comp_num = ([System.Console]::WindowHeight - 2) * ([math]::Floor([System.Console]::WindowWidth / ($max_len + 2)))
    $_input = $commandAst.CommandElements
    function _do($num) {
        $i = 0
        $completions.Keys | Where-Object { $_ -like "$_input*" } | ForEach-Object {
            $input_space_count = ($_input -split ' ').Count - 1
            $cmd_space_count = ($_ -split ' ').Count - 1
            if ($input_space_count -eq $cmd_space_count + $num ) {
                $i++
                if ($comp_num -gt $i) { $completions[$_] }
                else {
                    [CompletionResult]::new(" ", "...", 'ParameterValue', "...")
                    return
                }
            }
        }
    }
    _do $(if ($wordToComplete.length) { 0 }else { -1 })
    #endregion
}
