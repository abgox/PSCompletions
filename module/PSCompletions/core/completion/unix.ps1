Add-Member -InputObject $PSCompletions -MemberType ScriptMethod generate_completion {
    # XXX: 非 Windows 平台，暂时只能使用默认的补全菜单
    Set-PSReadLineKeyHandler $PSCompletions.config.trigger_key MenuComplete
}
Add-Member -InputObject $PSCompletions -MemberType ScriptMethod handle_completion {
    foreach ($_ in $PSCompletions.data.aliasMap.keys) {
        Register-ArgumentCompleter -CommandName $_ -ScriptBlock {
            param($word_to_complete, $command_ast, $cursor_position)

            $space_tab = if (!$word_to_complete.length) { 1 }else { 0 }

            $input_arr = @()
            $matches = [regex]::Matches($command_ast.CommandElements, "(?:`"[^`"]*`"|'[^']*'|\S)+")
            foreach ($match in $matches) { $input_arr += $match.Value }

            $alias = $input_arr[0]

            $PSCompletions.root_cmd = $root = $PSCompletions.data.aliasMap.$alias

            $input_arr = if ($input_arr.Count -le 1) { , @() } else { $input_arr[1..($input_arr.Count - 1)] }

            $filter_list = $PSCompletions.get_completion()
            $PSCompletions.menu.show_powershell_menu($filter_list)
        }
    }
}
