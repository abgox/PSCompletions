using namespace System.Management.Automation
using namespace System.Management.Automation.Language
Register-ArgumentCompleter -CommandName $_psc.comp_cmd.$template_comp -ScriptBlock {
    param($wordToComplete, $commandAst)

    $root_cmd = $_psc.comp_cmd.$template_comp

    #region : Parse json data
    $json = Get-Content -Raw -Path  ($PSScriptRoot + '\json\' + $_psc.lang + '.json') -Encoding UTF8 | ConvertFrom-Json
    $_json = $json.PSObject.Properties
    $json_info = $json.$template_comp_core_info
    #endregion

    #region : Store
    $completions = [ordered]@{}
    $_json | ForEach-Object {
        if ($_.Name -ne '$template_comp_core_info') {
            $cmd = $_.Name -split ' '
            $completions[$root_cmd + ' ' + $_.Name] = @($cmd[-1], $_.Value)
            $completions[$root_cmd + ' help ' + $cmd[0]] = @($cmd[0], ('Show help -- ' + $cmd[0]))
        }
    }
    #endregion

    #region : Carry out
    $_input = $commandAst.CommandElements
    $_input_str = $_input -join ' '
    $_input_arr = $_input_str -split '\s+'
    $max_len = 0
    $display_count = 0
    $cmd_line = [System.Console]::WindowHeight - 5
    $input_tab = if (!$wordToComplete.length) { 1 }else { 0 }
    $filter_list = $completions.Keys | Where-Object {
        $cmd = $_ -split '\s+'
        $position = [System.Collections.Generic.List[int]]@()
        for ($i = 0; $i -lt $cmd.Count; $i++) {
            if ($cmd[$i] -match '<.+>') { $position.Add($i) }
        }
        $_inputs = [System.Collections.Generic.List[string]]$_input_arr
        $flag = [System.Collections.Generic.List[string]]$cmd
        $position | ForEach-Object {
            if ($_inputs.Count -gt $_) {
                $flag.RemoveAt($_)
                $_inputs.RemoveAt($_)
            }
        }
        $cmd.Count -eq ($_input.Count + $input_tab) -and ($flag -join ' ') -like ($_inputs -join ' ') + '*'
    }
    $filter_list | ForEach-Object {
        $len = ($completions[$_][0].Replace('^up', ' ')).Length
        if ($len -ge $max_len) { $max_len = $len }
    }

    $comp_count = $cmd_line * [math]::Floor([System.Console]::WindowWidth / ($max_len + 2))

    $filter_list | ForEach-Object {
        if ($comp_count -gt $display_count) {
            $display_count++
            $display = $completions[$_][0].Replace('^up', ' ')
            [CompletionResult]::new($display, $display, 'ParameterValue', (_psc_replace $completions[$_][1]))
        }
        else {
            [CompletionResult]::new(' ', '...', 'ParameterValue', $_psc.json.comp_hide)
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
