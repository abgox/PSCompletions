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

                # 是否是按下空格键触发的补全
                $space_tab = if ($buffer[-1] -eq ' ') { 1 }else { 0 }
                # 使用正则表达式进行分割，将命令行中的每个参数分割出来，形成一个数组， 引号包裹的内容会被当作一个参数，且数组会包含 "--"
                $input_arr = @()
                $matches = [regex]::Matches($buffer, "(?:`"[^`"]*`"|'[^']*'|\S)+")
                foreach ($match in $matches) { $input_arr += $match.Value }

                # 触发补全的值，此值可能是别名或命令名
                $root = $alias = $input_arr[0]

                $PSCompletions.menu.by_TabExpansion2 = $false

                if ($PSCompletions.data.aliasMap[$alias] -ne $null -and $input_arr[-1] -notmatch '^(?:\.\.?|~)?(?:[/\\]).*') {
                    if ($buffer -eq $alias) { return }
                    # 原始的命令名，也是 completions 目录下的命令目录名
                    $PSCompletions.root_cmd = $root = $PSCompletions.data.aliasMap.$alias

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
                    foreach ($item in $completion.CompletionMatches) {
                        # XXX: 像 Get-*、Set-* 等内置命令的 ToolTip 会在每个示例的开头添加 4 个(空格或换行)，末尾添加 2 个(空格或换行)
                        # 因此，其他命令的 tip 不能在开头添加 4 个(空格或换行)，或者末尾添加 2 个(空格或换行)
                        # 这里通过 \s 去匹配空格或换行
                        $tip = @()
                        if ($item.ToolTip -match "^\s{4,}" -or $item.ToolTip -match ".*\s{2,}$") {
                            foreach ($i in $item.ToolTip -split "\s{4,}") {
                                $t = $i.Trim()
                                if ($t) {
                                    $tip += "$t`n`n"
                                }
                            }
                        }
                        else {
                            $tip += $item.ToolTip
                        }

                        $filter_list += @{
                            CompletionText = $item.CompletionText
                            ListItemText   = $item.ListItemText
                            ToolTip        = $tip
                        }
                    }

                    if ($PSCompletions.config.enable_completions_sort -eq 1 -and (Get-Command $alias -ErrorAction SilentlyContinue)) {
                        $path_order = "$($PSCompletions.path.order)/$root.json"
                        if ($PSCompletions.order."$($root)_job") {
                            if ($PSCompletions.order."$($root)_job".State -eq 'Completed') {
                                $PSCompletions.order.$root = Receive-Job $PSCompletions.order."$($root)_job"
                                Remove-Job $PSCompletions.order."$($root)_job"
                                $PSCompletions.order.Remove("$($root)_job")
                            }
                        }
                        else {
                            if (Test-Path $path_order) {
                                try {
                                    $PSCompletions.order.$root = $PSCompletions.ConvertFrom_JsonToHashtable($PSCompletions.get_raw_content($path_order))
                                }
                                catch {
                                    $PSCompletions.order.$root = $null
                                }
                            }
                            else {
                                $PSCompletions.order.$root = $null
                            }
                        }
                        $order = $PSCompletions.order.$root
                        if ($order) {
                            $PSCompletions._i = 0 # 这里使用 $PSCompletions._i 而非 $i 是因为在 Sort-Object 中，普通的 $i 无法累计
                            $filter_list = $filter_list | Sort-Object {
                                $PSCompletions._i --
                                # 不能使用 $order.($_.CompletionText)，它可能获取到对象中的 OverloadDefinitions
                                $o = $order[$_.CompletionText]
                                if ($o) { $o }else { $PSCompletions._i }
                            } -Descending -CaseSensitive
                        }
                        $PSCompletions.order_job((Get-PSReadLineOption).HistorySavePath, $root, $path_order)
                    }

                    $PSCompletions.menu.by_TabExpansion2 = $true
                    $result = $PSCompletions.menu.show_module_menu($filter_list)
                    # apply the completion
                    if ($result -ne $null) {
                        [Microsoft.PowerShell.PSConsoleReadLine]::Replace($completion.ReplacementIndex, $completion.ReplacementLength, $result)
                    }
                }
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

                    $PSCompletions.root_cmd = $root = $PSCompletions.data.aliasMap.$alias

                    $input_arr = if ($input_arr.Count -le 1) { , @() } else { $input_arr[1..($input_arr.Count - 1)] }

                    $filter_list = $PSCompletions.get_completion()

                    $PSCompletions.menu.by_TabExpansion2 = $false

                    if ($PSCompletions.config.enable_menu -eq 1) {
                        $PSCompletions.menu.show_module_menu($filter_list)
                    }
                    else {
                        $PSCompletions.menu.show_powershell_menu($filter_list)
                    }
                }
            }
        }
    }
}
