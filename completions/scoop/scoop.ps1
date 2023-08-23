using namespace System.Globalization
using namespace System.Management.Automation
using namespace System.Management.Automation.Language
Register-ArgumentCompleter -CommandName (_psc_get_cmd $PSScriptRoot 'scoop') -ScriptBlock {
    param($wordToComplete, $commandAst)

    $completions = [System.Collections.Specialized.OrderedDictionary]::new()

    #region : Parse json data
    $_name = $PSScriptRoot + '\json\' + $_psc.lang + '.json'
    $json = Get-Content -Raw -Path  $_name -Encoding UTF8 | ConvertFrom-Json
    $json_info =$json.scoop_core_info
    $_json = $json.PSObject.Properties
    #endregion

    #region : Store
    $max_len = 0
    foreach ($_ in $_json) {
        $subCmd = $_.Name.substring($_.Name.lastIndexOf(' ') + 1)
        if ($max_len -lt $subCmd.length) {
            $max_len = $subCmd.length
        }
        if ($_.Name -ne 'scoop_core_info') {
            $completions[(_psc_get_cmd $PSScriptRoot 'scoop') + ' ' + $_.Name] = [CompletionResult]::new($subcmd, $subcmd, 'ParameterValue', $_.Value)
        }
    }
    #endregion

    #region Special point
    $jsonData = Get-Content -Raw -Path "$env:userProfile\.config\scoop\config.json" | ConvertFrom-Json
    foreach ($_ in $jsonData.PSObject.Properties) {
        $name = "'" + $_.name + "'"
        $value = "'" + $_.Value + "'"
        $completions['scoop config ' + $name] = [CompletionResult]::new($name, $name, 'ParameterValue', $json_info.has_value + $value)
    }
    @("'use_external_7zip'", "'use_lessmsi'", "'no_junction'", "'scoop_repo'", "'scoop_branch'", "
	'proxy'", "'autostash_on_conflict'", "'default_architecture'", "'debug'", "
	'force_update'", "'show_update_log'", "'show_manifest'", "'shim'", "'root_path'", "
    'global_path'", "'cache_path'", "'gh_token'", "'virustotal_api_key'", "'cat_style'", "'ignore_running_processes'", "
	'private_hosts'", "'hold_update_until'", "'aria2-enabled'", "'aria2-warning-enabled'", "'aria2-retry-wait'", "'aria2-split'", "'aria2-max-connection-per-server'", "'aria2-min-split-size'", "'aria2-options'") | Where-Object {
        if (!$completions['scoop config ' + $_]) {
            $completions['scoop config ' + $_] = [CompletionResult]::new($_, $_, 'ParameterValue', $json_info.no_value)
        }
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
