# XXX: 必须使用 Add-Member

Add-Member -InputObject $PSCompletions -MemberType ScriptMethod generate_completion {
    $PSCompletions.use_module_menu = $PSCompletions.config.enable_menu

    if ($PSCompletions.config.enable_menu_enhance -and $PSCompletions.config.enable_menu) {
        Add-Member -InputObject $PSCompletions -MemberType ScriptMethod handle_completion {
            Set-PSReadLineKeyHandler -Key $PSCompletions.config.trigger_key -ScriptBlock {
                $buffer = ''
                $cursorPosition = 0
                [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$buffer, [ref]$cursorPosition)
                if (!$cursorPosition) {
                    return
                }

                $PSCompletions.need_ignore_suffix = $buffer[$cursorPosition] -eq ' '

                # 只获取当前光标位置之前的内容
                $buffer = $buffer.Substring(0, $cursorPosition)

                # 是否是按下空格键触发的补全
                $space_tab = if ($buffer[-1] -eq ' ') { 1 }else { 0 }
                # 使用正则表达式进行分割，将命令行中的每个参数分割出来，形成一个数组，引号包裹的内容会被当作一个参数，且数组会包含 "--"
                $input_arr = @()
                $matches = [regex]::Matches($buffer, $PSCompletions.input_pattern)
                foreach ($match in $matches) { $input_arr += $match.Value }

                if (!$input_arr) {
                    return
                }

                # 触发补全的值，此值可能是别名或命令名
                $root = $alias = $input_arr[0]

                $PSCompletions.menu.by_TabExpansion2 = $false

                if ($PSCompletions.data.aliasMap[$alias] -ne $null -and ($space_tab -or $input_arr.Count -gt 1) -and $input_arr[-1] -notmatch '^(?:\.\.?|~)?(?:[/\\]).*') {
                    # 原始的命令名，也是 completions 目录下的命令目录名
                    $PSCompletions.root_cmd = $root = $PSCompletions.data.aliasMap[$alias]

                    $input_arr = if ($input_arr.Count -le 1) { , @() } else { $input_arr[1..($input_arr.Count - 1)] }

                    $filter_list = $PSCompletions.get_completion()

                    if ($PSCompletions.config.completions_confirm_limit -gt 0 -and $filter_list.Count -gt $PSCompletions.config.completions_confirm_limit) {
                        $count = $filter_list.Count
                        $tip = $PSCompletions.replace_content($PSCompletions.info.module.too_many_completions.tip)
                        $_filter_list = foreach ($t in $PSCompletions.info.module.too_many_completions.text) {
                            $text = $PSCompletions.replace_content($t)
                            @{
                                CompletionText = $text
                                ListItemText   = $text
                                ToolTip        = $tip
                            }
                        }
                        $result = $PSCompletions.menu.show_module_menu($_filter_list)
                        if (!$result) {
                            return ''
                        }
                    }
                    $result = $PSCompletions.menu.show_module_menu($filter_list)
                    if ($result) {
                        if ($space_tab -or $PSCompletions.input_arr[-1] -like '-*=') {
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

                    $filter_list = $completion.CompletionMatches

                    if (!$filter_list) {
                        return
                    }

                    if ($PSCompletions.config.completions_confirm_limit -gt 0 -and $filter_list.Count -gt $PSCompletions.config.completions_confirm_limit) {
                        $count = $filter_list.Count
                        $tip = $PSCompletions.replace_content($PSCompletions.info.module.too_many_completions.tip)
                        $_filter_list = foreach ($t in $PSCompletions.info.module.too_many_completions.text) {
                            $text = $PSCompletions.replace_content($t)
                            @{
                                CompletionText = $text
                                ListItemText   = $text
                                ToolTip        = $tip
                            }
                        }
                        $result = $PSCompletions.menu.show_module_menu($_filter_list)
                        if (!$result) {
                            return ''
                        }
                    }

                    if ($root -eq 'PSCompletions') {
                        $has_command = foreach ($c in Get-Command) { if ($c.Name -eq $root) { $c; break } }
                    }
                    else {
                        $has_command = Get-Command $root -ErrorAction SilentlyContinue
                    }
                    if ($PSCompletions.config.enable_completions_sort -and $has_command) {
                        $path_order = "$($PSCompletions.path.order)/$root.json"
                        if ($PSCompletions.order."$($root)_job") {
                            if ($PSCompletions.order."$($root)_job".State -eq 'Completed') {
                                $PSCompletions.order[$root] = Receive-Job $PSCompletions.order."$($root)_job"
                                Remove-Job $PSCompletions.order."$($root)_job"
                                $PSCompletions.order.Remove("$($root)_job")
                            }
                        }
                        else {
                            if (Test-Path $path_order) {
                                try {
                                    $PSCompletions.order[$root] = $PSCompletions.ConvertFrom_JsonAsHashtable($PSCompletions.get_raw_content($path_order))
                                }
                                catch {
                                    $PSCompletions.order[$root] = $null
                                }
                            }
                            else {
                                $PSCompletions.order[$root] = $null
                            }
                        }
                        $order = $PSCompletions.order[$root]
                        if ($order) {
                            $PSCompletions._i = 0 # 这里使用 $PSCompletions._i 而非 $i 是因为在 Sort-Object 中，普通的 $i 无法累计
                            $filter_list = $filter_list | Sort-Object {
                                $PSCompletions._i --
                                # 不能使用 $order.($_.CompletionText)，它可能获取到对象中的 OverloadDefinitions
                                $o = $order[$_.CompletionText]
                                if ($o) { $o }
                                else {
                                    $o = $order[$_.CompletionText + $PSCompletions.separator]
                                    if ($o) { $o }else { $PSCompletions._i }
                                }
                            } -Descending -CaseSensitive
                        }
                        $PSCompletions.order_job((Get-PSReadLineOption).HistorySavePath, $root, $path_order)
                    }

                    $PSCompletions.menu.by_TabExpansion2 = $true
                    $result = $PSCompletions.menu.show_module_menu($filter_list)
                    # apply the completion
                    if ($result) {
                        [Microsoft.PowerShell.PSConsoleReadLine]::Replace($completion.ReplacementIndex, $completion.ReplacementLength, $result)
                    }
                }
            }
        }
    }
    else {
        if (!$PSCompletions.config.enable_menu_enhance) {
            Set-PSReadLineKeyHandler $PSCompletions.config.trigger_key MenuComplete
        }

        Add-Member -InputObject $PSCompletions -MemberType ScriptMethod handle_completion {
            $keys = $PSCompletions.data.aliasMap.keys
            foreach ($k in $keys) {
                Register-ArgumentCompleter -Native -CommandName $k -ScriptBlock {
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

                    $PSCompletions.menu.by_TabExpansion2 = $false

                    if ($PSCompletions.config.enable_menu) {
                        if ($PSCompletions.config.completions_confirm_limit -gt 0 -and $filter_list.Count -gt $PSCompletions.config.completions_confirm_limit) {
                            $count = $filter_list.Count
                            $tip = $PSCompletions.replace_content($PSCompletions.info.module.too_many_completions.tip)
                            $_filter_list = foreach ($t in $PSCompletions.info.module.too_many_completions.text) {
                                $text = $PSCompletions.replace_content($t)
                                @{
                                    CompletionText = $text
                                    ListItemText   = $text
                                    ToolTip        = $tip
                                }
                            }
                            $result = $PSCompletions.menu.show_module_menu($_filter_list)
                            if (!$result) {
                                return ''
                            }
                        }
                        $PSCompletions.menu.show_module_menu($filter_list)
                    }
                    else {
                        $PSCompletions.show_powershell_menu($filter_list)
                    }
                }
            }
        }
    }
}
