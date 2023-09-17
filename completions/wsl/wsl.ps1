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
    $_json | ForEach-Object {
        if ($_.Name -ne 'wsl_core_info') {
            $cmd = $_.Name -split ' '
            $completions[$root_cmd + ' ' + $_.Name] = @($cmd[-1], $_.Value)
        }
    }
    function clean_nul($data) {
        $res = [System.Collections.Generic.List[byte]]::new()
        [System.Text.Encoding]::UTF8.GetBytes($data) | ForEach-Object {
            # Remove NUL(0x00) characters from binary data
            if ($_ -ne 0x00) { $res.add($_) }
        }
        return [System.Text.Encoding]::UTF8.GetString($res)
    }

    $Distro_list = wsl -l -q | ForEach-Object { clean_nul $_ } | Where-Object { $_ -ne '' }
    #endregion

    #region Special point
    $Distro_list | ForEach-Object {
        $Distro = $_
        function _do($cmd, $tip) {
            $completions[$root_cmd + ' ' + $cmd + ' ' + $Distro] = @($Distro, $tip)
        }
        $temp = _psc_replace ($json_info.symbol + $json_info.Distro)
        _do '-d' $temp
        _do '~ -d' $temp
        _do '--distribution' $temp
        _do '~ --distribution' $temp
        $temp = _psc_replace $json_info.Distro
        _do '-u <user> -d' $temp
        _do '~ -u <user> -d' $temp
        _do '-u <user> --distribution' $temp
        _do '~ -u <user> --distribution' $temp
        _do '--user <user> -d' $temp
        _do '~ --user <user> -d' $temp
        _do '--user <user> --distribution' $temp
        _do '~ --user <user> --distribution' $temp
        _do '-s' ($json_info.s + $Distro)
        _do '--set-default' ($json_info.s + $Distro)
        _do '-t' (_psc_replace $json_info.Distro_t)
        _do '--terminate' (_psc_replace $json_info.Distro_t)
        _do '--unregister' (_psc_replace $json_info.Distro_u)
        _do '--export' (_psc_replace $json_info.Distro_e)
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
        $len = $completions[$_][0].Length
        if ($len -ge $max_len) { $max_len = $len }
    }

    $comp_count = $cmd_line * [math]::Floor([System.Console]::WindowWidth / ($max_len + 2))

    $filter_list | ForEach-Object {
        if ($comp_count -gt $display_count) {
            $display_count++
            [CompletionResult]::new($completions[$_][0], $completions[$_][0], 'ParameterValue', (_psc_replace $completions[$_][1]))
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
