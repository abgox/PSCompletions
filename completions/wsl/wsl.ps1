using namespace System.Globalization
using namespace System.Management.Automation
using namespace System.Management.Automation.Language
Register-ArgumentCompleter -CommandName $_psc.comp_cmd.wsl -ScriptBlock {
    param($wordToComplete, $commandAst)

    $root_cmd = $_psc.comp_cmd.wsl

    #region : Parse json data
    $json = Get-Content -Raw -Path  ($PSScriptRoot + '\json\' + $_psc.lang + '.json') -Encoding UTF8 | ConvertFrom-Json
    $_json = $json.PSObject.Properties
    $json_info = $json.wsl_core_info
    #endregion

    #region : Store
    $completions = [ordered]@{}
    function map_word($word) {
        $map_word = @(
            'a', 'b', 'c', 'd', 'e', 'f', 'g',
            'h', 'i', 'j', 'k', 'l', 'm', 'n',
            'o', 'p', 'q', 'r', 's', 't',
            'u', 'v', 'w', 'x', 'y', 'z',
            1, 2, 3, 4, 5, 6, 7, 8, 9, 0
            '-', '_'
        )
        $res = $word -split '' | Where-Object { $_ -in $map_word }
        return ($res -join '')
    }
    $Distro_list = wsl -l -q | Where-Object { $_ -ne '' } | ForEach-Object { map_word $_ }

    $_json | ForEach-Object {
        if ($_.Name -ne 'wsl_core_info') {
            $last_cmd = $_.Name.substring($_.Name.lastIndexOf(' ') + 1)
            $completions[$root_cmd + ' ' + $_.Name] = @($last_cmd, $_.Value)
        }
    }
    #endregion

    #region Special point
    $Distro_list | ForEach-Object {
        $Distro = $_
        $temp = _psc_replace ($json_info.symbol + $json_info.Distro)
        $completions[$root_cmd + ' -d ' + $Distro] = @($Distro, $temp)
        $completions[$root_cmd + ' ~ -d ' + $Distro] = @($Distro, $temp)
        $completions[$root_cmd + ' --distribution ' + $Distro] = @($Distro, $temp)
        $completions[$root_cmd + ' ~ --distribution ' + $Distro] = @($Distro, $temp)
        $completions[$root_cmd + ' -u <user> -d ' + $Distro] = @($Distro, $json_info.Distro)
        $completions[$root_cmd + ' ~ -u <user> -d ' + $Distro] = @($Distro, $json_info.Distro)
        $completions[$root_cmd + ' -u <user> --distribution ' + $Distro] = @($Distro, $json_info.Distro)
        $completions[$root_cmd + ' ~ -u <user> --distribution ' + $Distro] = @($Distro, $json_info.Distro)
        $completions[$root_cmd + ' --user <user> -d ' + $Distro] = @($Distro, $json_info.Distro)
        $completions[$root_cmd + ' ~ --user <user> -d ' + $Distro] = @($Distro, $json_info.Distro)
        $completions[$root_cmd + ' --user <user> --distribution ' + $Distro] = @($Distro, $json_info.Distro)
        $completions[$root_cmd + ' ~ --user <user> --distribution ' + $Distro] = @($Distro, $json_info.Distro)
        $completions[$root_cmd + ' -t ' + $Distro] = @($Distro, (_psc_replace $json_info.'Distro-t'))
        $completions[$root_cmd + ' --terminate ' + $Distro] = @($Distro, (_psc_replace $json_info.'Distro-t'))
        $completions[$root_cmd + ' --unregister ' + $Distro] = @($Distro, (_psc_replace $json_info.'Distro-u'))
        $completions[$root_cmd + ' --export ' + $Distro] = @($Distro, (_psc_replace $json_info.'Distro-e'))
    }
    #endregion

    #region : Carry out
    $_input = $commandAst.CommandElements
    $_input_str = $_input -join ' '
    $_input_arr = $_input_str -split '\s+'
    $limit_value = 0
    $limit_line = 0
    $display_count = 0
    $cmd_line = [System.Console]::WindowHeight - 4
    $input_tab = if (!$wordToComplete.length) { 1 }else { 0 }
    $filter_list = $completions.Keys | Where-Object {
        $cmd = $_ -split '\s+'
        $position = [System.Collections.Generic.List[int]]@()
        for ($i = 0; $i -lt $cmd.Count; $i++) {
            if ($cmd[$i] -match "<.+>") { $position.Add($i) }
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
        $len = $completions[$_][0].Length
        if ($len -ge $limit_value) { $limit_value = $len }
        $line = ($completions[$_][1] -split "`n").Count
        if ($line -ge $limit_line) { $limit_line = $line }
    }
    $comp_count = ($cmd_line - $limit_line ) * [math]::Floor([System.Console]::WindowWidth / ($limit_value + 2))

    $filter_list | ForEach-Object {
        if ($comp_count -gt $display_count) {
            $display_count++
            [CompletionResult]::new($completions[$_][0], $completions[$_][0], 'ParameterValue', (_psc_replace $completions[$_][1]))
        }
        else {
            [CompletionResult]::new(" ", "...", 'ParameterValue', $_psc.json.comp_hide)
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
