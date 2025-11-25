Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod parse_list {
    # X
    if ($config.enable_list_follow_cursor) {
        $menu.pos.X = $rawUI.CursorPosition.X
        # 如果跟随鼠标，且超过右侧边界，则向左偏移
        $edge = $rawUI.BufferSize.Width - 1 - $menu.ui_width
        if ($edge -lt $menu.pos.X) {
            $menu.pos.X = $edge
        }
    }
    else {
        $menu.pos.X = 0
    }

    # Y
    $menu.ui_height = $menu.filter_list.Count + 2
    if ($menu.is_show_above) {
        if ($menu.cursor_to_top -lt $menu.ui_height) {
            $menu.ui_height = $menu.cursor_to_top
        }
        $list_limit = if ($config.list_max_count_when_above -eq -1) { 12 }else { $config.list_max_count_when_above + 2 }
        if ($list_limit -lt $menu.ui_height) {
            $menu.ui_height = $list_limit
        }
        $menu.pos.Y = $rawUI.CursorPosition.Y - $menu.ui_height - $config.height_from_menu_bottom_to_cursor_when_above
    }
    else {
        if ($menu.cursor_to_bottom -lt $menu.ui_height) {
            $menu.ui_height = $menu.cursor_to_bottom
        }
        $list_limit = if ($config.list_max_count_when_below -eq -1) { 12 }else { $config.list_max_count_when_below + 2 }
        if ($list_limit -lt $menu.ui_height) {
            $menu.ui_height = $list_limit
        }
        $menu.pos.Y = $rawUI.CursorPosition.Y + 1
    }
    $menu.page_max_index = $menu.ui_height - 3
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod get_buffer {
    param($startPos, $endPos)

    $top = New-Object System.Management.Automation.Host.Coordinates $startPos.X, $startPos.Y
    $bottom = New-Object System.Management.Automation.Host.Coordinates $endPos.X , $endPos.Y
    $buffer = $rawUI.GetBufferContents((New-Object System.Management.Automation.Host.Rectangle $top, $bottom))
    @{
        top    = $top
        bottom = $bottom
        buffer = $buffer
    }
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod new_buffer {
    # XXX: 在 Windows PowerShell 5.x 中，边框使用以下符号以处理兼容性问题
    if ($PSEdition -ne 'Core') {
        $horizontal = '-'
        $vertical = '|'
        $top_left = '+'
        $bottom_left = '+'
        $top_right = '+'
        $bottom_right = '+'
    }
    else {
        $horizontal = $config.horizontal
        $vertical = $config.vertical
        $top_left = $config.top_left
        $bottom_left = $config.bottom_left
        $top_right = $config.top_right
        $bottom_right = $config.bottom_right
    }

    $border_box = @()
    $content_box = @()
    $list_area = $menu.list_max_width

    $border_box += [string]$top_left + $horizontal * $list_area + $top_right

    $line = [string]$vertical + ' ' * $list_area + [string]$vertical
    $content = ' ' * $list_area
    foreach ($_ in 0..($menu.ui_height - 3)) {
        $border_box += $line
        $content_box += $content
    }

    $status = "$(([string]($menu.selected_index + 1)).PadLeft($menu.filter_list.Count.ToString().Length, ' '))"

    $border_box += [string]$bottom_left + $horizontal * 2 + ' ' * ($status.Length + 1) + $horizontal * ($list_area - $status.Length - 3) + $bottom_right

    $rawUI.SetBufferContents($menu.pos, $rawUI.NewBufferCellArray($border_box, $config.border_text, $config.border_back))

    $rawUI.SetBufferContents(@{
            X = $menu.pos.X + 1
            Y = $menu.pos.Y + 1
        }, $rawUI.NewBufferCellArray($content_box, $config.item_text, $config.item_back)
    )
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod new_list_buffer {
    param([int]$offset)

    $lines = $offset..($menu.ui_height - 3 + $offset)
    $content_box = foreach ($_ in $lines) {
        $text = $menu.filter_list[$_].ListItemText
        $text + ' ' * ($menu.list_max_width - $menu.get_length($text))
    }
    $rawUI.SetBufferContents(@{
            X = $menu.pos.X + 1
            Y = $menu.pos.Y + 1
        },
        $rawUI.NewBufferCellArray($content_box, $config.item_text, $config.item_back)
    )
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod new_filter_buffer {
    param([string]$filter)

    $char = $config.filter_symbol
    $middle = [System.Math]::Ceiling($char.Length / 2)
    $start = $char.Substring(0, $middle)
    $end = $char.Substring($middle)

    $rawUI.SetBufferContents(
        @{
            X = $menu.pos.X + 2
            Y = $menu.pos.Y
        },
        $rawUI.NewBufferCellArray(@(@($start, $filter, $end) -join ''), $config.filter_text, $config.filter_back)
    )
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod new_status_buffer {
    $X = $menu.pos.X + 3
    if ($menu.is_show_above) {
        $Y = $rawUI.CursorPosition.Y - 1 - $config.height_from_menu_bottom_to_cursor_when_above
    }
    else {
        $Y = $menu.pos.Y + $menu.ui_height - 1
    }

    $current = "$(([string]($menu.selected_index + 1)).PadLeft($menu.filter_list.Count.ToString().Length, ' '))"
    $rawUI.SetBufferContents(@{ X = $X; Y = $Y }, $rawUI.NewBufferCellArray(@("$current$($config.status_symbol)$($menu.filter_list.Count)"), $config.status_text, $config.status_back))
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod new_tip_buffer {
    param([int]$index)

    if ($menu.is_show_above) {
        $start = 0
        $line = $menu.pos.Y
    }
    else {
        $start = $menu.pos.Y + $menu.ui_height
        $line = $rawUI.BufferSize.Height - $start
    }
    if ($line -gt 0) {
        $content = ' ' * $rawUI.BufferSize.Width
        $box = foreach ($_ in 1..$line) { $content }
        $rawUI.SetBufferContents(
            @{
                X = 0
                Y = $start
            },
            $rawUI.NewBufferCellArray($box, $bgColor, $bgColor)
        )
    }

    if ($menu.is_show_tip) {
        if ($menu.is_show_above) {
            $rest_line = $menu.cursor_to_top - $menu.ui_height
        }
        else {
            $rest_line = $menu.cursor_to_bottom - $menu.ui_height
        }
        if ($rest_line -le 0) {
            return
        }

        $tip = $menu.filter_list[$index].ToolTip
        if ($tip -ne $null) {
            $json = $PSCompletions.completions.$($PSCompletions.root_cmd)
            $info = $json.info

            $tip_arr = @()

            $lineWidth = $rawUI.BufferSize.Width
            if ($config.enable_tip_follow_cursor) {
                $lineWidth -= $rawUI.CursorPosition.X
            }

            $tips = $PSCompletions.replace_content($tip).Split("`n").Where({ $_ -ne '' })
            foreach ($v in $tips) {
                $currentWidth = 0
                $outputString = ''
                $currentLine = ''
                $char_record = @{}
                $chars = $v.ToCharArray()
                foreach ($char in $chars) {
                    if ($char_record.ContainsKey($char)) {
                        $charWidth = $char_record[$char]
                    }
                    else {
                        $charWidth = $rawUI.NewBufferCellArray($char, $bgColor, $bgColor).LongLength
                        $char_record[$char] = $charWidth
                    }

                    if ($currentWidth + $charWidth -gt $lineWidth) {
                        $outputString += $currentLine + "`n"
                        $currentLine = ''
                        $currentWidth = 0
                    }
                    $currentLine += $char
                    $currentWidth += $charWidth
                }

                $outputString += $currentLine

                $tip_arr += ($outputString).Split("`n")
            }

            if ($tip_arr.Count -eq 0) {
                return
            }

            $pos = @{
                X = if ($config.enable_tip_follow_cursor) { $menu.pos.X }else { 0 }
                Y = $menu.pos.Y + $menu.ui_height + 1
            }
            $full = $rest_line - $tip_arr.Count

            if ($menu.is_show_above) {
                if ($full -lt 0) {
                    $pos.Y = 0
                    $maxIndex = $tip_arr.Count + $full - 1
                }
                else {
                    $pos.Y = $full
                    $maxIndex = $tip_arr.Count - 1
                }
                $tip_arr = $tip_arr[0..$maxIndex]
            }
            else {
                if ($pos.Y -ge $rawUI.BufferSize.Height - 1) {
                    return
                }
            }
            $rawUI.SetBufferContents($pos, $rawUI.NewBufferCellArray($tip_arr, $config.tip_text, $config.tip_back))
        }
    }
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod set_selection {
    if ($menu.old_selection) {
        $rawUI.SetBufferContents($menu.old_selection.pos, $menu.old_selection.buffer)
    }

    $X = $menu.pos.X + 1
    $to_X = $X + $menu.list_max_width - 1

    # 当前页的第几个
    $Y = $menu.pos.Y + 1 + $menu.page_current_index

    # 根据坐标，生成需要被改变内容的矩形，也就是要被选中的项
    $Rectangle = New-Object System.Management.Automation.Host.Rectangle $X, $Y, $to_X, $Y

    # 通过矩形，获取到这个矩形中的原本的内容
    $LineBuffer = $rawUI.GetBufferContents($Rectangle)
    $menu.old_selection = @{
        pos    = @{
            X = $X
            Y = $Y
        }
        buffer = $LineBuffer
    }
    # 给原本的内容设置前景颜色和背景颜色
    # XXX: 对于多字节字符，需要过滤掉 Trailing 类型字符以确保正确渲染
    $LineBuffer = $LineBuffer.Where({ $_.BufferCellType -ne 'Trailing' })
    $content = foreach ($i in $LineBuffer) { $i.Character }
    $rawUI.SetBufferContents(@{ X = $X; Y = $Y }, $rawUI.NewBufferCellArray(@([string]::Join('', $content)), $config.selected_text, $config.selected_back))
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod move_selection {
    param([bool]$isDown)

    $moveDirection = if ($isDown) { 1 } else { -1 }

    $is_move = if ($isDown) {
        $menu.page_current_index -lt $menu.page_max_index
    }
    else {
        $menu.page_current_index -gt 0
    }

    $new_selected_index = $menu.selected_index + $moveDirection

    if ($config.enable_list_loop) {
        $menu.selected_index = ($new_selected_index + $menu.filter_list.Count) % $menu.filter_list.Count
    }
    else {
        $menu.selected_index = if ($new_selected_index -lt 0) {
            0
        }
        elseif ($new_selected_index -ge $menu.filter_list.Count) {
            $menu.filter_list.Count - 1
        }
        else {
            $new_selected_index
        }
    }

    if ($is_move) {
        $menu.page_current_index = ($menu.page_current_index + $moveDirection) % ($menu.page_max_index + 1)
        if ($menu.page_current_index -lt 0) {
            $menu.page_current_index += $menu.page_max_index + 1
        }
        $menu.set_selection()
        $menu.new_status_buffer()
        $menu.new_tip_buffer($menu.selected_index)
        $menu.handle_data('edit')
        return
    }

    if ($config.enable_list_loop -or ($new_selected_index -ge 0 -and $new_selected_index -lt $menu.filter_list.Count)) {
        if ($isDown) {
            if ($menu.selected_index -eq 0) {
                $menu.page_current_index -= $menu.page_max_index
            }
        }
        else {
            if ($menu.selected_index -eq $menu.filter_list.Count - 1) {
                $menu.page_current_index += $menu.page_max_index
            }
        }

        $menu.offset = ($menu.offset + $moveDirection) % ($menu.filter_list.Count - $menu.page_max_index)
        if ($menu.offset -lt 0) {
            $menu.offset += $menu.filter_list.Count - $menu.page_max_index
        }

        $menu.old_selection = $null
        $menu.new_list_buffer($menu.offset)
        $menu.set_selection()
        $menu.new_filter_buffer($menu.filter)
        $menu.new_status_buffer()
        $menu.new_tip_buffer($menu.selected_index)
        $menu.handle_data('edit')
    }
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod reset {
    param([bool]$clearAll = $true)
    if ($clearAll) {
        $menu.data.Clear()
        if ($menu.origin_full_buffer) {
            $rawUI.SetBufferContents($menu.origin_full_buffer.top, $menu.origin_full_buffer.buffer)
            $menu.origin_full_buffer = $null
        }
    }
    $menu.old_selection = $null
    $menu.offset = 0
    $menu.selected_index = 0
    $menu.page_current_index = 0
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod handle_data {
    param([string]$type)

    switch ($type) {
        add {
            $menu.data.Add(
                @{
                    page_current_index = $menu.page_current_index
                    page_max_index     = $menu.page_max_index
                    selected_index     = $menu.selected_index
                    offset             = $menu.offset
                    filter             = $menu.filter
                    filter_list        = $menu.filter_list
                    old_selection      = $menu.old_selection.Clone()
                    old_full_buffer    = $menu.get_buffer($menu.buffer_start, $menu.buffer_end)

                    # XXX: 这里必须使用基础类型，否则有可能出现数据不一致，导致菜单塌陷
                    ui_height          = $menu.ui_height
                    pos_y              = $menu.pos.Y
                }
            )
        }
        get {
            $data = $menu.data[-1]
            $menu.page_current_index = $data.page_current_index
            $menu.page_max_index = $data.page_max_index
            $menu.selected_index = $data.selected_index
            $menu.offset = $data.offset
            $menu.filter = $data.filter
            $menu.filter_list = $data.filter_list
            $menu.old_selection = $data.old_selection

            # XXX: 这里必须使用基础类型，否则有可能出现数据不一致，导致菜单塌陷
            $menu.ui_height = $data.ui_height
            $menu.pos.Y = $data.pos_y
        }
        edit {
            $menu.data[-1] = @{
                page_current_index = $menu.page_current_index
                page_max_index     = $menu.page_max_index
                selected_index     = $menu.selected_index
                offset             = $menu.offset
                filter             = $menu.filter
                filter_list        = $menu.filter_list
                old_selection      = $menu.old_selection.Clone()
                old_full_buffer    = $menu.get_buffer($menu.buffer_start, $menu.buffer_end)

                # XXX: 这里必须使用基础类型，否则有可能出现数据不一致，导致菜单塌陷
                ui_height          = $menu.ui_height
                pos_y              = $menu.pos.Y
            }
        }
    }
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod show_module_menu {
    param($filter_list)

    $menu = $PSCompletions.menu
    $config = $PSCompletions.config
    $rawUI = $Host.UI.RawUI
    $bgColor = $rawUI.BackgroundColor

    if ($rawUI.BufferSize.Height -lt 5) {
        [Microsoft.PowerShell.PSConsoleReadLine]::UndoAll()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($PSCompletions.info.min_area)
        return ''
    }
    if (!$filter_list) { return '' }

    $suffix = $config.completion_suffix

    function handleOutput($item) {
        $out = $item.CompletionText

        # 不是由 TabExpansion2 获取的补全，即通过 psc add 添加的补全
        if ($null -eq $item.ResultType) {
            return "$out$suffix"
        }

        if ($item.ResultType -in @(
                [System.Management.Automation.CompletionResultType]::Method,
                [System.Management.Automation.CompletionResultType]::Property,
                [System.Management.Automation.CompletionResultType]::Variable,
                [System.Management.Automation.CompletionResultType]::Type,
                [System.Management.Automation.CompletionResultType]::Namespace
            )) {
            return $out
        }

        # Directory, registry key, or other container types
        if ($item.ResultType -eq [System.Management.Automation.CompletionResultType]::ProviderContainer) {
            if ($config.enable_path_with_trailing_separator) {
                if ($out.Length -ge 1 -and $out[-1] -match "^['`"]$") {
                    if ($out.Length -ge 2 -and $out[-2] -match "^[/\\]$") {
                        return $out
                    }
                    return $out.Insert($out.Length - 1, $PSCompletions.separator)
                }
                return $out + $PSCompletions.separator
            }
            return $out
        }

        # File or other leaf items (e.g., registry values)
        # [System.Management.Automation.CompletionResultType]::ProviderItem

        # [System.Management.Automation.CompletionResultType]::Command

        # [System.Management.Automation.CompletionResultType]::ParameterName

        # [System.Management.Automation.CompletionResultType]::ParameterValue

        # if foreach switch ...
        # [System.Management.Automation.CompletionResultType]::Keyword

        # [System.Management.Automation.CompletionResultType]::Text

        return "$out$suffix"
    }

    $menu.pos = @{ X = 0; Y = 0 }

    $menu.ui_width = 0
    $menu.ui_height = 0
    $menu.list_max_width = $config.list_min_width

    $menu.filter = ''  # 过滤的关键词

    $menu.page_current_index = 0 # 当前显示页中的索引

    $menu.selected_index = 0  # 当前选中项的实际索引

    $menu.offset = 0  # 索引的偏移量，用于滚动翻页

    # 记录每一次过滤的数据
    $menu.data = [System.Collections.Generic.List[System.Object]]::new()

    if ($menu.by_TabExpansion2) {
        $menu.is_show_tip = $config.enable_tip_when_enhance
    }
    else {
        $enable_tip = $config.comp_config.$($PSCompletions.root_cmd).enable_tip
        if ($null -eq $enable_tip) {
            $menu.is_show_tip = $config.enable_tip
        }
        else {
            $menu.is_show_tip = $enable_tip
        }
    }

    $menu.filter_list = [System.Collections.Generic.List[System.Object]]::new()
    $maxWidth = $menu.list_max_width
    foreach ($item in $filter_list) {
        $len = $menu.get_length($item.ListItemText)
        if ($len -gt $maxWidth) {
            $maxWidth = $len
        }
        $menu.filter_list.Add($item)
    }
    $menu.list_max_width = $maxWidth
    $menu.ui_width = $maxWidth + 2

    if ($config.enable_enter_when_single -and $menu.filter_list.Count -eq 1) {
        return handleOutput $menu.filter_list[0]
    }

    $current_encoding = [console]::OutputEncoding
    [console]::OutputEncoding = $PSCompletions.encoding

    $menu.cursor_to_bottom = $rawUI.BufferSize.Height - $rawUI.CursorPosition.Y - 1
    $menu.cursor_to_top = $rawUI.CursorPosition.Y - $config.height_from_menu_bottom_to_cursor_when_above - 1

    $menu.is_show_above = $menu.cursor_to_bottom -lt $menu.cursor_to_top

    if ($menu.is_show_above) {
        $startY = 0
        $endY = $menu.cursor_to_top
    }
    else {
        $startY = $rawUI.CursorPosition.Y + 1
        $endY = $rawUI.BufferSize.Height - 1
    }

    $menu.buffer_start = New-Object System.Management.Automation.Host.Coordinates 0, $startY
    $menu.buffer_end = New-Object System.Management.Automation.Host.Coordinates ($rawUI.BufferSize.Width - 1), $endY

    $menu.parse_list()

    # 如果解析后的菜单高度小于 3 (上下边框 + 1个补全项)
    if ($menu.ui_height -lt 3 -or $menu.ui_width -gt $rawUI.BufferSize.Width - 2) {
        [Microsoft.PowerShell.PSConsoleReadLine]::UndoAll()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($PSCompletions.info.min_area)
        return ''
    }

    # 显示菜单之前，记录 buffer
    $menu.origin_full_buffer = $menu.get_buffer($menu.buffer_start, $menu.buffer_end)

    # 显示菜单
    $menu.new_buffer()
    $menu.new_list_buffer($menu.offset)
    $menu.set_selection()
    $menu.new_filter_buffer($menu.filter)
    $menu.new_status_buffer()
    $menu.new_tip_buffer($menu.selected_index)

    $menu.handle_data('add')

    :loop while (($PressKey = $rawUI.ReadKey('NoEcho,IncludeKeyDown,AllowCtrlC')).VirtualKeyCode) {
        $pressShift = 0x10 -band [int]$PressKey.ControlKeyState
        $pressCtrl = $PressKey.ControlKeyState -like '*CtrlPressed*'

        switch ($PressKey.VirtualKeyCode) {
            9 {
                # 9: Tab
                if ($menu.filter_list.Count -eq 1) {
                    $menu.reset()
                    handleOutput $menu.filter_list[$menu.selected_index]
                    break loop
                }
                $menu.move_selection(!$pressShift)
                break
            }
            { $_ -eq 27 -or ($pressCtrl -and $_ -eq 67) } {
                # 27: ESC
                # 67: Ctrl + c
                $menu.reset()
                ''
                break loop
            }
            { $_ -in @(32, 13) } {
                # 32: Space
                # 13: Enter
                handleOutput $menu.filter_list[$menu.selected_index]
                $menu.reset()
                break loop
            }

            # 向上
            # 37: Up
            # 38: Left
            # 85: Ctrl + u
            # 80: Ctrl + p
            # 75: Ctrl + k
            { $_ -in @(37, 38) -or ($pressCtrl -and $_ -in @(85, 80, 75)) } {
                $menu.move_selection($false)
                break
            }
            # 向下
            # 39: Right
            # 40: Down
            # 68: Ctrl + d
            # 78: Ctrl + n
            # 74: Ctrl + j
            { $_ -in @(39, 40) -or ($pressCtrl -and $_ -in @(68, 78, 74)) } {
                $menu.move_selection($true)
                break
            }
            # filter character
            { $PressKey.Character } {
                # remove
                if ($PressKey.Character -eq 8) {
                    # 8: Backspace
                    if ($menu.filter) {
                        $menu.filter = $menu.filter.Substring(0, $menu.filter.Length - 1)
                    }
                    else {
                        $menu.reset()
                        ''
                        break loop
                    }

                    if ($menu.data.Count -gt 1) {
                        $old_buffer = $menu.data[-2].old_full_buffer
                        $rawUI.SetBufferContents($old_buffer.top, $old_buffer.buffer)
                        $menu.data.RemoveAt($menu.data.Count - 1)
                    }
                    else {
                        $old_buffer = $menu.data[0].old_full_buffer
                        $rawUI.SetBufferContents($old_buffer.top, $old_buffer.buffer)
                        $menu.data.Clear()
                    }

                    $menu.handle_data('get')
                }
                else {
                    # add
                    if ($menu.filter -match '\*$' -and $PressKey.Character -eq '*') {
                        break
                    }
                    $menu.filter += $PressKey.Character

                    $escapedFilter = $menu.filter -replace '(\[|\])', '`$1'
                    if ($escapedFilter.StartsWith('^')) {
                        $comparison = {
                            param($text)
                            $text -like $escapedFilter.Substring(1) + '*'
                        }
                    }
                    else {
                        $comparison = {
                            param($text)
                            $text -like "*$escapedFilter*"
                        }
                    }
                    $resultList = [System.Collections.Generic.List[System.Object]]::new()
                    $list = $menu.filter_list
                    foreach ($f in $list) {
                        if ($comparison.Invoke($f.ListItemText)) {
                            $resultList.Add($f)
                        }
                    }
                    $menu.filter_list = $resultList.ToArray()

                    if (!$menu.filter_list) {
                        $menu.filter = $menu.data[-1].filter
                        $menu.filter_list = $menu.data[-1].filter_list
                    }
                    else {
                        $menu.reset($false)
                        $menu.parse_list()
                        $menu.new_buffer()
                        $menu.new_list_buffer($menu.offset)
                        $menu.new_tip_buffer($menu.selected_index)
                        $menu.new_status_buffer()
                        $menu.new_filter_buffer($menu.filter)
                        $menu.set_selection(0)

                        $menu.handle_data('add')
                    }
                }
                break
            }
        }
    }
    [console]::OutputEncoding = $current_encoding
}
