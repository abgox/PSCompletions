$PSCompletions.methods['generate_completion'] = {
    $PSCompletions.use_module_menu = 0

    # XXX: 非 Windows 平台，暂时只能使用默认的补全菜单
    Set-PSReadLineKeyHandler $PSCompletions.config.trigger_key MenuComplete
}
$PSCompletions.methods['handle_completion'] = {
    $keys = $PSCompletions.data.aliasMap.keys
    foreach ($_ in $keys) {
        Register-ArgumentCompleter -Native -CommandName $_ -ScriptBlock {
            param($word_to_complete, $command_ast, $cursor_position)

            $space_tab = if ($word_to_complete.length) { 0 }else { 1 }

            $input_arr = @()
            $matches = [regex]::Matches($command_ast.CommandElements, $PSCompletions.input_pattern)
            foreach ($match in $matches) { $input_arr += $match.Value }

            if (!$input_arr) {
                return
            }

            $alias = $input_arr[0]

            $PSCompletions.root_cmd = $root = $PSCompletions.data.aliasMap[$alias]

            $input_arr = if ($input_arr.Count -le 1) { , @() } else { $input_arr[1..($input_arr.Count - 1)] }

            $filter_list = $PSCompletions.get_completion()
            $PSCompletions.show_powershell_menu($filter_list)
        }
    }
}
