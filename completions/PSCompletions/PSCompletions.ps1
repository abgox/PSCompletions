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
    $max_len = 0
    foreach ($_ in $_json) {
        $subCmd = $_.Name.substring($_.Name.lastIndexOf(' ') + 1)
        if ($max_len -lt $subCmd.length) {
            $max_len = $subCmd.length
        }
        if ($_.Name -ne 'PSCompletions_core_info') {
            $completions[ $root_cmd + ' ' + $_.Name] = [CompletionResult]::new($subcmd, $subcmd, 'ParameterValue', (_psc_replace $_.value))
        }
    }
    #endregion

    #region Special point
    foreach ($_ in $_psc.list) {
        if ($_ -notin $_psc.installed.BaseName) {
            $completions[ $root_cmd + ' add ' + $_] = [CompletionResult]::new($_, $_, 'ParameterValue', (_psc_replace $_psc.json.add) )
        }
    }
    if ($_psc.update) {
        foreach ($_ in $_psc.update) {
            $completions[ $root_cmd + ' update ' + $_] = [CompletionResult]::new($_, $_, 'ParameterValue', (_psc_replace $_psc.json.update))
        }
    }
    foreach ($_ in $_psc.installed.BaseName) {
        $completions[$root_cmd + ' rm ' + $_] = [CompletionResult]::new($_, $_, 'ParameterValue', (_psc_replace $_psc.json.remove))
        $completions[$root_cmd + ' which ' + $_] = [CompletionResult]::new($_, $_, 'ParameterValue', (_psc_replace $_psc.json.which))
    }
    foreach ($_ in @('root_cmd', 'github', 'gitee', 'language', 'update')) {
        $completions[$root_cmd + ' config ' + $_] = [CompletionResult]::new($_, $_, 'ParameterValue', (_psc_replace ($_psc.json.config + $json.('config ' + $_))))
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
        if ($i -eq 1) { Write-Output ' ' }
    }
    _do $(if ($wordToComplete.length) { 0 }else { -1 })
    #endregion

    #region
    try {
        $history = (Get-History)[-1].CommandLine
    }
    catch {
        $history = ''
    }
    $null = Start-Job -ScriptBlock {
        param( $_psc, $history, $root)
        function _do($flag, $path) {
            $json = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
            $res = [ordered]@{}
            $max = 0
            $cmd_len = 0
            $res_flag = $null
            foreach ($_ in $json.PSObject.Properties) {
                $type = ($_.value).GetType().Name
                if ($type -eq 'String') {
                    $cmd = $_.Name -split ' '
                    $count = (Compare-Object $cmd $flag -IncludeEqual -ExcludeDifferent -PassThru).Count
                    if ($count -gt $max) {
                        $cmd_len = $cmd.Count
                        $max = $count
                        $res_flag = $_.Name
                    }
                    elseif ($count -eq $max) {
                        if ($cmd_len -gt $cmd.Count) {
                            $max = $count
                            $res_flag = $_.Name
                        }
                    }
                }
            }
            foreach ($_ in $json.PSObject.Properties) {
                $type = ($_.value).GetType().Name
                if ($type -eq 'String') {
                    if ($_.Name -eq $res_flag) {
                        $res.Insert(0, $_.Name, $_.value)
                    }
                    else { $res.($_.Name) = $_.value }
                }
                else { $res.($_.Name) = $_.value }
            }
            $res  | ConvertTo-Json | Out-File $path
        }
        if ($history -ne '') {
            $cmd = $history -split ' '
            $alias = $_psc.comp_cmd.keys | foreach-Object { $_psc.comp_cmd.$_ }
            if ($cmd[0] -in $alias) {
                _do $cmd[1..($cmd.Length - 1)] ($root + '\json\' + $_psc.lang + '.json')
            }
        }
    } -ArgumentList $_psc, $history, $PSScriptRoot
    #endregion
}
