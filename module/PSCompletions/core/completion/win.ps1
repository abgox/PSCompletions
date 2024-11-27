Add-Member -InputObject $PSCompletions -MemberType ScriptMethod generate_completion {
    if ($PSCompletions.config.enable_menu_enhance -and $PSCompletions.config.enable_menu) {
        Add-Member -InputObject $PSCompletions -MemberType ScriptMethod handle_completion {
            Set-PSReadLineKeyHandler -Key $PSCompletions.config.trigger_key -ScriptBlock {
                $buffer = ''
                $cursorPosition = 0
                [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$buffer, [ref]$cursorPosition)
                if (!$cursorPosition) {
                    return
                }

                # Windows PowerShell 5.x
                if ($PSEdition -ne 'Core') {
                    $PSCompletions.config.horizontal = '-'
                    $PSCompletions.config.vertical = '|'
                    $PSCompletions.config.top_left = '+'
                    $PSCompletions.config.bottom_left = '+'
                    $PSCompletions.config.top_right = '+'
                    $PSCompletions.config.bottom_right = '+'
                }

                # 是否是按下空格键触发的补全
                $space_tab = if ($buffer[-1] -eq ' ') { 1 }else { 0 }
                # 使用正则表达式进行分割，将命令行中的每个参数分割出来，形成一个数组， 引号包裹的内容会被当作一个参数，且数组会包含 "--"
                $input_arr = @()
                $matches = [regex]::Matches($buffer, "(?:`"[^`"]*`"|'[^']*'|\S)+")
                foreach ($match in $matches) { $input_arr += $match.Value }

                # 触发补全的值，此值可能是别名或命令名
                $alias = $input_arr[0]

                if ($PSCompletions.data.aliasMap.$alias -ne $null -and $input_arr[-1] -notmatch '^(?:\.\.?|~)?(?:[/\\]).*') {
                    if ($buffer -eq $alias) { return }
                    # 原始的命令名，也是 completions 目录下的命令目录名
                    $PSCompletions.current_cmd = $root = $PSCompletions.data.aliasMap.$alias

                    $input_arr = if ($input_arr.Count -le 1) { , @() } else { $input_arr[1..($input_arr.Count - 1)] }

                    $filter_list = $PSCompletions.get_completion()
                    $result = $PSCompletions.menu.show_module_menu($filter_list)
                    if ($result -ne $null) {
                        if ($space_tab) {
                            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($result)
                        }
                        else {
                            $input_arr = if ($input_arr.Count -le 1) { , @() } else { $input_arr[0..($input_arr.Count - 2)] }
                            $result = if ($input_arr.Count -eq 0) { "$alias $result" }else { "$alias $($input_arr -join ' ') $result" }
                            [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $buffer.Length, $result)
                        }
                    }
                }
                else {
                    try {
                        $completion = TabExpansion2 $buffer $cursorPosition
                    }
                    catch {
                        return
                    }
                    if (!$completion.CompletionMatches) {
                        return
                    }

                    $filter_list = @()
                    $runspacePool = [runspacefactory]::CreateRunspacePool(1, [Environment]::ProcessorCount)
                    $runspacePool.Open()
                    $runspaces = @()

                    foreach ($completions in $PSCompletions.split_array($completion.CompletionMatches, [Environment]::ProcessorCount, $true)) {
                        $runspace = [powershell]::Create().AddScript({
                                param($completions, $host_ui)
                                $max_width = 0
                                $results = @()
                                function get_length {
                                    param([string]$str)
                                    $host_ui.RawUI.NewBufferCellArray($str, $host_ui.RawUI.BackgroundColor, $host_ui.RawUI.BackgroundColor).LongLength
                                }
                                foreach ($completion in $completions) {
                                    if ($completion.ToolTip -ne $null) {
                                        if ($completion.ResultType -in @('ParameterValue', 'ParameterName')) {
                                            $tool_tip = $completion.ToolTip
                                        }
                                        else {
                                            # 如果是内置命令，由于其 ToolTip 写法很奇怪，会导致显示的内容有些问题
                                            $tool_tip = @()
                                            foreach ($tip in $completion.ToolTip) {
                                                $tip = $tip -replace '\s{2}', ' '

                                                $guid = [guid]::NewGuid()
                                                $tip = $tip -replace '\s{2}', $guid

                                                $tool_tip += $tip.Trim() -split $guid
                                            }
                                            $tool_tip = $tool_tip -join "`n`n"
                                        }
                                        $results += @{
                                            ListItemText   = $completion.ListItemText
                                            CompletionText = $completion.CompletionText
                                            ToolTip        = $tool_tip
                                        }
                                    }
                                    else {
                                        $results += $completion
                                    }
                                    $max_width = [Math]::Max($max_width, (get_length $completion.ListItemText))
                                }
                                @{
                                    results   = $results
                                    max_width = $max_width
                                }
                            }).AddArgument($completions).AddArgument($Host.UI)
                        $runspace.RunspacePool = $runspacePool
                        $runspaces += @{ Runspace = $runspace; Job = $runspace.BeginInvoke() }
                    }
                    foreach ($rs in $runspaces) {
                        $result = $rs.Runspace.EndInvoke($rs.Job)
                        $rs.Runspace.Dispose()
                        $PSCompletions.menu.list_max_width = [Math]::Max($PSCompletions.menu.list_max_width, $result.max_width)
                        if ($result.results) {
                            $filter_list += $result.results
                        }
                    }

                    $result = $PSCompletions.menu.show_module_menu($filter_list, $true)
                    # apply the completion
                    if ($result -ne $null) {
                        [Microsoft.PowerShell.PSConsoleReadLine]::Replace($completion.ReplacementIndex, $completion.ReplacementLength, $result)
                    }
                }
                $PSCompletions.current_cmd = $null
            }
        }
    }
    else {
        Add-Member -InputObject $PSCompletions -MemberType ScriptMethod handle_completion {
            foreach ($_ in $PSCompletions.data.aliasMap.keys) {
                Register-ArgumentCompleter -CommandName $_ -ScriptBlock {
                    param($word_to_complete, $command_ast, $cursor_position)

                    $space_tab = if (!$word_to_complete.length) { 1 }else { 0 }

                    $input_arr = @()
                    $matches = [regex]::Matches($command_ast.CommandElements, "(?:`"[^`"]*`"|'[^']*'|\S)+")
                    foreach ($match in $matches) { $input_arr += $match.Value }

                    $alias = $input_arr[0]

                    $PSCompletions.current_cmd = $root = $PSCompletions.data.aliasMap.$alias

                    $input_arr = if ($input_arr.Count -le 1) { , @() } else { $input_arr[1..($input_arr.Count - 1)] }

                    $filter_list = $PSCompletions.get_completion()
                    if ($PSCompletions.config.enable_menu -eq 1) {
                        # Windows PowerShell 5.x
                        if ($PSEdition -ne 'Core') {
                            $PSCompletions.config.horizontal = '-'
                            $PSCompletions.config.vertical = '|'
                            $PSCompletions.config.top_left = '+'
                            $PSCompletions.config.bottom_left = '+'
                            $PSCompletions.config.top_right = '+'
                            $PSCompletions.config.bottom_right = '+'
                        }
                        $PSCompletions.menu.show_module_menu($filter_list)
                    }
                    else {
                        $PSCompletions.menu.show_powershell_menu($filter_list)
                    }
                    $PSCompletions.current_cmd = $null
                }
            }
        }
    }
}
