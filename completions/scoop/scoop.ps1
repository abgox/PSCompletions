using namespace System.Management.Automation
using namespace System.Management.Automation.Language
Register-ArgumentCompleter -CommandName $_psc.comp_cmd.scoop -ScriptBlock {
    param($wordToComplete, $commandAst)

    $root_cmd = $_psc.comp_cmd.scoop

    #region : Store
    $json = _psc_parse_json_with_LRU $PSScriptRoot
    $json_info = $json.scoop_core_info
    $completions = [ordered]@{}
    _psc_generate_order $PSScriptRoot | ForEach-Object {
        $cmd = $_ -split ' '
        $completions[$root_cmd + ' ' + $_] = @($cmd[-1], $json.$_)
        $completions[$root_cmd + ' help ' + $cmd[0]] = @($cmd[0], ($json_info.help + ' --- ' + $cmd[0]))
    }
    #endregion

    #region Special point
    $symbol = $json_info.symbol
    if ($env:SCOOP) {
        $scoop_path = $env:SCOOP
    }
    else {
        $path = (Get-Content -Raw "$env:UserProfile\.config\scoop\config.json" | ConvertFrom-Json).root_path
        if ($path) { [environment]::SetEnvironmentvariable('SCOOP', $path, 'User') }
        $scoop_path = $path
    }

    if ($env:SCOOP_GLOBAL) {
        $scoop_global_path = $env:SCOOP_GLOBAL
    }
    else {
        $path = (Get-Content -Raw "$env:UserProfile\.config\scoop\config.json" | ConvertFrom-Json).global_path
        if ($path) { [environment]::SetEnvironmentvariable('SCOOP_GLOBAL', $path, 'User') }
        $scoop_global_path = $path
    }

    Get-ChildItem "$scoop_path\buckets" 2>$null | ForEach-Object {
        $completions[$root_cmd + ' bucket rm ' + $_.Name] = @($_.Name, ('Remove bucket --- ' + $_.Name))
    }

    function return_str($str) {
        return ($symbol + $str + ' app --- ' + $_.Name + "`n" + $_.FullName)
    }
    Get-ChildItem "$scoop_path\apps" 2>$null | ForEach-Object {
        function _do($cmd, $tip) {
            $completions[$root_cmd + ' ' + $cmd + ' ' + $_.Name] = @($_.Name, $tip)
        }
        _do 'uninstall' (return_str 'Uninstall')
        _do 'update' (return_str 'Update')
        _do 'cleanup' (return_str 'Cleanup')
        _do 'hold' (return_str 'Hold')
        _do 'unhold' (return_str 'Unhold')
        _do 'prefix' $_.FullName
    }
    Get-ChildItem "$scoop_global_path\apps" 2>$null | ForEach-Object {
        function _do($cmd, $tip) {
            $cmd = $root_cmd + ' ' + $cmd + ' ' + $_.Name
            if ($completions[$cmd]) {
                $completions[$cmd] = @($_.Name, ($completions[$cmd][1] + "`n" + $_.FullName))
            }
            else {
                $completions[$cmd] = @($_.Name, $tip)
            }
        }
        _do 'uninstall' (return_str 'Uninstall')
        _do 'update' (return_str 'Update')
        _do 'cleanup' (return_str 'Cleanup')
        _do 'hold' (return_str 'Hold')
        _do 'unhold' (return_str 'Unhold')
        _do 'prefix' $_.FullName
    }
    #endregion

    #region : Carry out
    $_input = $commandAst.CommandElements
    $max_len = 0
    $display_count = 0
    $cmd_line = [System.Console]::WindowHeight - 5
    $input_tab = if (!$wordToComplete.length) { 1 }else { 0 }
    $filter_list = $completions.Keys | Where-Object {
        $cmd = $_ -split ' '
        $position = [System.Collections.Generic.List[int]]@()
        for ($i = 0; $i -lt $cmd.Count; $i++) {
            if ($cmd[$i] -like '<*>') { $position.Add($i) }
        }
        $_inputs = [System.Collections.Generic.List[string]]$_input
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
            $item = $completions[$_][0]
            [CompletionResult]::new($item, $item, 'ParameterValue', (_psc_replace $completions[$_][1]))
        }
        else {
            [CompletionResult]::new(' ', '...', 'ParameterValue', $_psc.json.comp_hide)
            return
        }
    }
    if ($display_count -eq 1) { ' ' }
    #endregion

    _psc_reorder_tab  $PSScriptRoot
}
