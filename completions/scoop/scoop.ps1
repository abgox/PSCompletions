<#
# @Author      : abgox
# @Github      : https://github.com/abgox/PS-completions
#>

using namespace System.Globalization
using namespace System.Management.Automation
using namespace System.Management.Automation.Language
Register-ArgumentCompleter -CommandName (_psc_get_cmd $PSScriptRoot 'scoop') -ScriptBlock {
    param($wordToComplete, $commandAst)

    $completions = [System.Collections.Specialized.OrderedDictionary]::new()

    if ($_psc.lang -eq 'zh-CN') {
        $scoop_config_help1 = '当前值 --  '
        $scoop_config_help2 = '值未设置'
    }
    else {
        $scoop_config_help1 = 'Current value --  '
        $scoop_config_help2 = 'It has not been set'
    }

    #region : Parse json data
    $_name = $PSScriptRoot + '\json\' + $_psc.lang + '.json'
    $_json = (Get-Content -Raw -Path  $_name -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties
    #endregion

    #region : Store all tab-completion
    foreach ($_ in $_json) {
        $subCmd = $_.Name.substring($_.Name.lastIndexOf(' ') + 1)
        $completions[(_psc_get_cmd $PSScriptRoot 'scoop') + ' ' + $_.Name] = [CompletionResult]::new($subcmd, $subcmd, 'ParameterValue', $_.Value)
    }
    #endregion


    #region Special point
    $jsonData = Get-Content -Raw -Path "$env:userProfile\.config\scoop\config.json" | ConvertFrom-Json
    foreach ($_ in $jsonData.PSObject.Properties) {
        $name = "'" + $_.name + "'"
        $value = "'" + $_.Value + "'"
        $completions['scoop config ' + $name] = [CompletionResult]::new($name, $name, 'ParameterValue', $scoop_config_help1 + $value)
    }
    @("'use_external_7zip'", "'use_lessmsi'", "'no_junction'", "'scoop_repo'", "'scoop_branch'", "
	'proxy'", "'autostash_on_conflict'", "'default_architecture'", "'debug'", "
	'force_update'", "'show_update_log'", "'show_manifest'", "'shim'", "'root_path'", "
    'global_path'", "'cache_path'", "'gh_token'", "'virustotal_api_key'", "'cat_style'", "'ignore_running_processes'", "
	'private_hosts'", "'hold_update_until'", "'aria2-enabled'", "'aria2-warning-enabled'", "'aria2-retry-wait'", "'aria2-split'", "'aria2-max-connection-per-server'", "'aria2-min-split-size'", "'aria2-options'") | Where-Object {
        if (!$completions['scoop config ' + $_]) {
            $completions['scoop config ' + $_] = [CompletionResult]::new($_, $_, 'ParameterValue', $scoop_config_help2)
        }
    }
    #endregion

    #region : Carry out
    $_input = $commandAst.CommandElements
    function completion($num) {

        $completions.Keys | Where-Object { $_ -like "$_input*" } | ForEach-Object {
            $input_space_count = ($_input -split ' ').Count - 1
            $cmd_space_count = ($_ -split ' ').Count - 1
            if ($input_space_count -eq $cmd_space_count + $num) { $completions[$_] }
        }
    }
    completion $(if ($wordToComplete.length) { 0 }else { -1 })
    #endregion
}
