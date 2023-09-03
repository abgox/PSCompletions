using namespace System.Globalization
using namespace System.Management.Automation
using namespace System.Management.Automation.Language
Register-ArgumentCompleter -CommandName $_psc.comp_cmd.wsl -ScriptBlock {
    param($wordToComplete, $commandAst)

    $root_cmd = $_psc.comp_cmd.wsl

    #region : Parse json data
    $json = Get-Content -Raw -Path  ($PSScriptRoot + '\json\' + $_psc.lang + '.json') -Encoding UTF8 | ConvertFrom-Json
    $_json = $json.PSObject.Properties
    # #endregion

    #region : Store
    $completions = [ordered]@{}
    foreach ($_ in $_json) {
        if ($_.Name -ne 'wsl_core_info') {
            $subCmd = $_.Name.substring($_.Name.lastIndexOf(' ') + 1)
            $cmd = $root_cmd + ' ' + $_.Name
            $cmd_arr = $cmd -split ' '
            $position = @()
            for ($i = 0; $i -lt $cmd_arr.Count; $i++) {
                if ($cmd_arr[$i] -match "<.+>") { $position += $i }
            }
            $completions[$cmd] = @([CompletionResult]::new($subcmd, $subcmd, 'ParameterValue', (_psc_replace $_.value)), $subCmd.length, ($_.Value -split "`n").Count) + $position
        }
    }
    #endregion

    #region : Carry out
    $_input = $commandAst.CommandElements
    $limit_value = 0
    $limit_line = 0
    $display_count = 0
    $cmd_line = [System.Console]::WindowHeight - 4
    $input_tab = if ($wordToComplete.length) { $true }else { $false }
    $filter_list = $completions.Keys | Where-Object {
        $cmd = $_ -split '\s+'
        $temp = $cmd[0..($_input.Count - 1)]
        if ($input_tab) {
            $cmd.Count -eq $_input.Count -and $temp -join ' ' -like ($_input -join ' ') + '*'
        }
        else {
            if ($completions[$_].Count -gt 3) {
                $info = $completions[$_]
                $first = ($info[4..($info.Length - 1)])[0]
                $result = $cmd.Count -eq ($_input.Count + 1) -and $cmd[$first - 1] -eq $_input[$first - 1]
            }
            else {
                $result = $cmd.Count -eq ($_input.Count + 1) -and ($temp -join ' ') -eq $_input
            }
            $result
        }
    }
    $filter_list | ForEach-Object {
        if ($completions[$_][1] -ge $limit_value) { $limit_value = $completions[$_][1] }
        if ($completions[$_][2] -ge $limit_line) { $limit_line = $completions[$_][2] }
    }
    $comp_count = ($cmd_line - $limit_line ) * [math]::Floor([System.Console]::WindowWidth / ($limit_value + 2))

    if ($comp_count -le [math]::Floor($filter_list.Count * 2 / 3)) {
        $comp_count = $cmd_line * [math]::Floor([System.Console]::WindowWidth / ($limit_value + 2))
    }
    $filter_list | ForEach-Object {
        if ($comp_count -gt $display_count) { $display_count++; $completions[$_][0] }
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
