Add-Member -InputObject $PSCompletions -MemberType ScriptMethod handle_completion {
    param([string]$cmd)
    $this.cmd[$cmd] | ForEach-Object {
        Register-ArgumentCompleter -CommandName $_ -ScriptBlock {
            param($word_to_complete, $command_ast, $cursor_position)
            # 使用正则表达式进行分割，将命令行中的每个参数分割出来，形成一个数组， 引号包裹的内容会被当作一个参数，且数组会包含 "--"
            $regex = "(?:`"[^`"]*`"|'[^']*'|\S)+"
            $matches = [regex]::Matches($command_ast.CommandElements, $regex)

            $input_arr = New-Object System.Collections.Generic.List[string]
            foreach ($match in $matches) { $input_arr.Add($match.Value) }

            # 触发补全的值，此值可能是别名或命令名
            $alias = $input_arr[0]

            # 原始的命令名，也是 completions 目录下的命令目录名
            $PSCompletions.current_cmd = $root = $PSCompletions.alias.$alias

            $input_arr.RemoveAt(0)

            # 获取 json 数据
            if ($PSCompletions.data.Count -eq 0) {
                if ($PSCompletions.job.State -eq 'Completed') {
                    $data = Receive-Job $PSCompletions.job
                    $data.Keys | ForEach-Object {
                        $PSCompletions.data.$_ = $data.$_
                    }
                    Remove-Job $PSCompletions.job
                    $PSCompletions.job = $null
                }
            }
            if (!$PSCompletions.data.$root -or $PSCompletions.config.disable_cache) {
                $language = $PSCompletions.get_language($root)
                $PSCompletions.data.$root = $PSCompletions.get_raw_content("$($PSCompletions.path.completions)/$($root)/language/$($language).json") | ConvertFrom-Json -AsHashtable
            }

            $common_options = if ($PSCompletions.data.$root.common_options) {
                $PSCompletions.data.$root.common_options | ForEach-Object { $_.name }
            }
            else { New-Object System.Collections.ArrayList }
            $WriteSpaceTab = [System.Collections.Generic.List[string]]@()

            $WriteSpaceTab_and_SpaceTab = [System.Collections.Generic.List[string]]@()

            # 存储别名的映射，用于在过滤时允许别名
            $alias_map = @{}

            function getCompletions {
                $completions = [System.Collections.Generic.List[System.Object]]@()
                $index = 1
                function parseCompletions ($node, $pre, [switch]$isOption) {
                    $node | ForEach-Object {
                        $pad = if ($pre) { ' ' }else { '' }
                        $symbols = @()
                        if ($isOption) {
                            $symbols += 'OptionTab'
                        }
                        if ($_.next -or $_.options) {
                            $symbols += 'SpaceTab'
                            if ($isOption) {
                                $symbols += 'WriteSpaceTab'
                            }
                        }
                        if ($_.symbol) {
                            $symbols += $PSCompletions.replace_content($_.symbol, ' ') -split ' '
                        }
                        $symbols = $symbols | Select-Object -Unique

                        $completions.Add(@{
                                name   = $pre + $pad + $_.name
                                symbol = $symbols
                                tip    = $_.tip
                            })
                        if ($_.alias) {
                            if ($isOption) {
                                foreach ($a in $_.alias) {
                                    $completions.Add(@{
                                            name   = $pre + $pad + $a
                                            symbol = $symbols
                                            tip    = $_.tip
                                        })
                                    if ($_.next) { parseCompletions $_.next ($pre + $pad + $a) }
                                }
                            }
                            else {
                                foreach ($a in $_.alias) {
                                    # 判断别名出现的位置
                                    $index = (($pre + $pad + $_.name) -split ' ').Length - 1
                                    # 用这个位置创建一个数组，将所有在这个位置出现的别名全部写入这个数组
                                    if (!($alias_map[$index])) { $alias_map[$index] = @() }
                                    $alias_map[$index] += @{
                                        name  = $_.name
                                        alias = $a
                                    }
                                    $completions.Add(@{
                                            name   = $pre + $pad + $a
                                            symbol = $symbols
                                            tip    = $_.tip
                                        })
                                }
                            }
                        }
                        if ($symbols) {
                            if ('WriteSpaceTab' -in $symbols) {
                                $WriteSpaceTab.Add($_.name)
                                if ($_.alias) {
                                    foreach ($a in $_.alias) { $WriteSpaceTab.Add($a) }
                                }
                                if ('SpaceTab' -in $symbols) {
                                    $WriteSpaceTab_and_SpaceTab.Add($_.name)
                                    if ($_.alias) {
                                        foreach ($a in $_.alias) { $WriteSpaceTab_and_SpaceTab.Add($a) }
                                    }
                                }
                            }
                        }
                        if ($_.next) { parseCompletions $_.next ($pre + $pad + $_.name) }
                        if ($_.options) { parseCompletions $_.options ($pre + $pad + $_.name) -isOption }
                    }
                }
                if ($PSCompletions.data.$root.root) { parseCompletions $PSCompletions.data.$root.root '' }
                if ($PSCompletions.data.$root.options) { parseCompletions $PSCompletions.data.$root.options '' -isOption }
                return $completions
            }
            function handleCompletions($completions) { return $completions }
            function filterCompletions($completions, $root) {
                # 是否是按下空格键触发的补全
                $space_tab = if (!$word_to_complete.length) { 1 }else { 0 }

                # 当这个 options 是 WriteSpaceTab 时，将下一个值直接过滤掉
                $need_skip = $false

                $filter_input_arr = [System.Collections.Generic.List[string]]@()
                $input_arr | ForEach-Object {
                    if ($_ -like '-*' -or $need_skip) {
                        if ($need_skip) { $need_skip = $false }
                        if ($_ -in $WriteSpaceTab) {
                            if ($input_arr[-1 - !$space_tab] -eq $_ -and $_ -in $WriteSpaceTab_and_SpaceTab) {
                                $need_add = $true
                            }
                            else {
                                $need_skip = $true
                            }
                        }
                    }
                    else { $need_add = $true }
                    if ($need_add -and $_ -notin $common_options) {
                        $filter_input_arr.Add($_)
                        $need_add = $false
                    }
                }

                if (!$space_tab) {
                    # 如果是输入 -* 过程中触发的补全，则需要把最后一个 -* 加入其中
                    if ($input_arr[-1] -like '-*') {
                        $filter_input_arr += $input_arr[-1]
                    }
                }

                if ($filter_input_arr.Count) {
                    $match = if ($space_tab) { ' *' }else { '*' }
                }
                else {
                    # 如果过滤出来为空，则是只是输入了根命令，没有输入其他内容
                    $match = '*'
                }

                $filter_list = [System.Collections.Generic.List[System.Object]]@()
                $completions | ForEach-Object {
                    $matches = [regex]::Matches($_.name, "(?:`"[^`"]*`"|'[^']*'|\S)+")
                    $cmd = [System.Collections.Generic.List[string]]@()
                    foreach ($m in $matches) { $cmd.Add($m.Value) }
                    <#
                        判断选项是否使用过了，如果使用过了，$no_used 为 $true
                        这里的判断对于 --file="abc" 这样的命令无法使用，因为这里和用户输入的 "abc"是连着的
                    #>
                    $no_used = if ($cmd[-1] -like '-*') {
                        $cmd[-1] -notin $input_arr
                    }
                    else { $true }

                    $alias_input_arr = $filter_input_arr

                    # 循环命令的长度，针对每一个位置去 $alias_map 找到对应的数组，然后把数组里的值拿出来比对，如果有匹配的，替换掉原来的命令名
                    # 用位置的好处是，这样遍历是依赖于命令的长度，而命令长度一般不长
                    for ($i = 0; $i -lt $filter_input_arr.Count; $i++) {
                        if ($alias_map[$i]) {
                            foreach ($obj in $alias_map[$i]) {
                                if ($obj.alias -eq $filter_input_arr[$i]) {
                                    $alias_input_arr[$i] = $obj.name
                                    break
                                }
                            }
                        }
                    }
                    $isLike = ($_.name -like ([WildcardPattern]::Escape($filter_input_arr -join ' ') + $match)) -or ($_.name -like ([WildcardPattern]::Escape($alias_input_arr -join ' ') + $match))

                    if ($no_used -and $cmd.Count -eq ($filter_input_arr.Count + $space_tab) -and $isLike) {
                        # 让 name 的值变成一个数组，方便后面处理
                        $_.name = $cmd
                        $filter_list.Add($_)
                    }
                }

                # 处理 common_options
                if ($PSCompletions.data.$root.common_options) {
                    if ($space_tab) {
                        $PSCompletions.data.$root.common_options | Where-Object { $_.name -notin $input_arr } | ForEach-Object {
                            $symbols = @('OptionTab')
                            if ($_.symbol) {
                                $symbols += $PSCompletions.replace_content($_.symbol, ' ') -split ' '
                            }
                            $symbols = $symbols | Select-Object -Unique
                            if ($_.alias) {
                                foreach ($a in $_.alias) {
                                    $filter_list.Add(@{
                                            name   = @($a)
                                            symbol = $symbols
                                            tip    = $_.tip
                                        })
                                }
                            }
                            $_.name = @($_.name)
                            $_.symbol = $symbols
                            $filter_list.Add($_)
                        }
                    }
                    else {
                        $PSCompletions.data.$root.common_options | Where-Object { $_.name -notin $input_arr -and $_.name -like "$($filter_input_arr[-1])*" } | ForEach-Object {
                            $_.name = @($_.name)
                            $filter_list.Add($_)
                        }
                    }
                }

                return $filter_list
            }

            if ($PSCompletions.config.comp_config.$root.disable_hooks -ne 1) {
                # 使用 hooks 覆盖默认的函数，实现在一些特殊的需求，比如一些补全的动态加载
                $path_hook = "$($PSCompletions.path.completions)/$($root)/hooks.ps1"
                if (Test-Path $path_hook) { . $path_hook }
            }

            $completions = getCompletions
            $completions = handleCompletions $completions
            $filter_list = filterCompletions $completions $root

            # 排序
            if ($PSCompletions.config.menu_completions_sort) {
                $path_order = "$($PSCompletions.path.completions)/$($root)/order.json"
                if ($PSCompletions.order."$($root)_job") {
                    if ($PSCompletions.order."$($root)_job".State -eq 'Completed') {
                        $PSCompletions.order.$root = Receive-Job $PSCompletions.order."$($root)_job"
                        Remove-Job $PSCompletions.order."$($root)_job"
                        $PSCompletions.order.Remove("$($root)_job")
                    }
                }
                else {
                    if (Test-Path $path_order) {
                        $PSCompletions.order.$root = $PSCompletions.get_raw_content($path_order) | ConvertFrom-Json -AsHashtable
                    }
                    else {
                        $PSCompletions.order.$root = $null
                    }
                }
                $order = $PSCompletions.order.$root
                if ($order) {
                    $filter_list = $filter_list | Sort-Object {
                        $o = $order.$($_.name -join ' ')
                        if ($o) { $o }else { 999999999 }
                    }
                }

                $PSCompletions.order."$($root)_job" = Start-Job -ScriptBlock {
                    param($PScompletions, $completions, $path_history, $root, $path_order)
                    $order = [ordered]@{}
                    $index = 1
                    $completions | ForEach-Object {
                        $order.$($_.name -join ' ') = $index
                        $index++
                    }
                    $historys = [System.Collections.Generic.List[string]]@()
                    Get-Content $path_history -Encoding utf8 -ErrorAction SilentlyContinue | ForEach-Object {
                        foreach ($alias in $PSCompletions.cmd.$root) {
                            if ($_ -match "^[^\S\n]*$($alias)\s+.+") {
                                $historys.Add($_)
                                break
                            }
                        }
                    }
                    $index = -1
                    function handle_order([array]$history) {
                        $str = $history -join ' '
                        if ($str -in $order.Keys) {
                            $order.$str = $index
                        }
                        if ($history.Count -eq 1) {
                            return
                        }
                        else {
                            handle_order $history[0..($history.Count - 2)]
                        }
                    }

                    $historys | ForEach-Object {
                        $matches = [regex]::Matches($_, "(?:`"[^`"]*`"|'[^']*'|\S)+")
                        $cmd = [System.Collections.Generic.List[string]]@()
                        foreach ($m in $matches) { $cmd.Add($m.Value) }
                        if ($cmd.Count -gt 1) {
                            handle_order $cmd[1..($cmd.Count - 1)]
                            $index--
                        }
                    }
                    $json = $order | ConvertTo-Json -Compress
                    $matches = [regex]::Matches($json, '\s*"\s*"\s*:')
                    foreach ($match in $matches) {
                        $json = $json -replace $match.Value, "`"empty_key_$([System.Guid]::NewGuid().Guid)`":"
                    }
                    $json | Out-File $path_order -Encoding utf8 -Force
                    return $order
                } -ArgumentList $PScompletions, $completions, (Get-PSReadLineOption).HistorySavePath, $root, $path_order
            }

            $menu_show_tip = $PSCompletions.config.comp_config.$root.menu_show_tip
            if ($menu_show_tip -ne $null) {
                $PSCompletions.menu.is_show_tip = $menu_show_tip -eq 1
            }
            else {
                $PSCompletions.menu.is_show_tip = $PSCompletions.config.menu_show_tip -eq 1
            }
            if ($PSCompletions.config.menu_enable) {
                $PSCompletions.menu.show_module_menu($filter_list)
            }
            else {
                $PSCompletions.menu.show_powershell_menu($filter_list)
            }
        }
    }
}
