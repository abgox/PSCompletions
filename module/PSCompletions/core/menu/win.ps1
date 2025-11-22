Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod parse_list {
    # X
    if ($PSCompletions.config.enable_list_follow_cursor) {
        $PSCompletions.menu.pos.X = $Host.UI.RawUI.CursorPosition.X
        # 如果跟随鼠标，且超过右侧边界，则向左偏移
        $PSCompletions.menu.pos.X = [Math]::Min($PSCompletions.menu.pos.X, $Host.UI.RawUI.BufferSize.Width - 1 - $PSCompletions.menu.ui_width)
    }
    else {
        $PSCompletions.menu.pos.X = 0
    }

    # Y
    $PSCompletions.menu.ui_height = $PSCompletions.menu.filter_list.Count + 2
    if ($PSCompletions.menu.is_show_above) {
        $PSCompletions.menu.ui_height = [Math]::Min($PSCompletions.menu.cursor_to_top, $PSCompletions.menu.ui_height)
        $list_limit = if ($PSCompletions.config.list_max_count_when_above -eq -1) { 12 }else { $PSCompletions.config.list_max_count_when_above + 2 }
        $PSCompletions.menu.ui_height = [Math]::Min($list_limit, $PSCompletions.menu.ui_height)
        $PSCompletions.menu.pos.Y = $Host.UI.RawUI.CursorPosition.Y - $PSCompletions.menu.ui_height - $PSCompletions.config.height_from_menu_bottom_to_cursor_when_above
    }
    else {
        $PSCompletions.menu.ui_height = [Math]::Min($PSCompletions.menu.cursor_to_bottom, $PSCompletions.menu.ui_height)
        $list_limit = if ($PSCompletions.config.list_max_count_when_below -eq -1) { 12 }else { $PSCompletions.config.list_max_count_when_below + 2 }
        $PSCompletions.menu.ui_height = [Math]::Min($list_limit, $PSCompletions.menu.ui_height)
        $PSCompletions.menu.pos.Y = $Host.UI.RawUI.CursorPosition.Y + 1
    }
    $PSCompletions.menu.page_max_index = $PSCompletions.menu.ui_height - 3
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod get_buffer {
    param($startPos, $endPos)
    $top = New-Object System.Management.Automation.Host.Coordinates $startPos.X, $startPos.Y
    $bottom = New-Object System.Management.Automation.Host.Coordinates $endPos.X , $endPos.Y
    $buffer = $Host.UI.RawUI.GetBufferContents((New-Object System.Management.Automation.Host.Rectangle $top, $bottom))
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
        $horizontal = $PSCompletions.config.horizontal
        $vertical = $PSCompletions.config.vertical
        $top_left = $PSCompletions.config.top_left
        $bottom_left = $PSCompletions.config.bottom_left
        $top_right = $PSCompletions.config.top_right
        $bottom_right = $PSCompletions.config.bottom_right
    }

    $border_box = @()
    $content_box = @()
    $list_area = $PSCompletions.menu.list_max_width

    $border_box += [string]$top_left + $horizontal * $list_area + $top_right

    $line = [string]$vertical + ' ' * $list_area + [string]$vertical
    $content = ' ' * $list_area
    foreach ($_ in 0..($PSCompletions.menu.ui_height - 3)) {
        $border_box += $line
        $content_box += $content
    }

    $status = "$(([string]($PSCompletions.menu.selected_index + 1)).PadLeft($PSCompletions.menu.filter_list.Count.ToString().Length, ' '))"

    $border_box += [string]$bottom_left + $horizontal * 2 + ' ' * ($status.Length + 1) + $horizontal * ($list_area - $status.Length - 3) + $bottom_right

    $Host.UI.RawUI.SetBufferContents($PSCompletions.menu.pos, $Host.UI.RawUI.NewBufferCellArray($border_box, $PSCompletions.config.border_text, $PSCompletions.config.border_back))

    $Host.UI.RawUI.SetBufferContents(@{
            X = $PSCompletions.menu.pos.X + 1
            Y = $PSCompletions.menu.pos.Y + 1
        }, $Host.UI.RawUI.NewBufferCellArray($content_box, $PSCompletions.config.item_text, $PSCompletions.config.item_back)
    )
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod new_list_buffer {
    param([int]$offset)
    $content_box = @()
    foreach ($_ in $offset..($PSCompletions.menu.ui_height - 3 + $offset)) {
        $content_length = $PSCompletions.menu.get_length($PSCompletions.menu.filter_list[$_].ListItemText)
        $content = $PSCompletions.menu.filter_list[$_].ListItemText + ' ' * ($PSCompletions.menu.list_max_width - $content_length)
        $content_box += $content
    }
    $Host.UI.RawUI.SetBufferContents(@{
            X = $PSCompletions.menu.pos.X + 1
            Y = $PSCompletions.menu.pos.Y + 1
        },
        $Host.UI.RawUI.NewBufferCellArray($content_box, $PSCompletions.config.item_text, $PSCompletions.config.item_back)
    )
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod new_filter_buffer {
    param([string]$filter)
    $char = $PSCompletions.config.filter_symbol
    $middle = [System.Math]::Ceiling($char.Length / 2)
    $start = $char.Substring(0, $middle)
    $end = $char.Substring($middle)

    $buffer_filter = $Host.UI.RawUI.NewBufferCellArray(@(@($start, $filter, $end) -join ''), $PSCompletions.config.filter_text, $PSCompletions.config.filter_back)
    $Host.UI.RawUI.SetBufferContents(
        @{
            X = $PSCompletions.menu.pos.X + 2
            Y = $PSCompletions.menu.pos.Y
        },
        $buffer_filter
    )
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod new_status_buffer {
    $X = $PSCompletions.menu.pos.X + 3
    if ($PSCompletions.menu.is_show_above) {
        $Y = $Host.UI.RawUI.CursorPosition.Y - 1 - $PSCompletions.config.height_from_menu_bottom_to_cursor_when_above
    }
    else {
        $Y = $PSCompletions.menu.pos.Y + $PSCompletions.menu.ui_height - 1
    }

    $current = "$(([string]($PSCompletions.menu.selected_index + 1)).PadLeft($PSCompletions.menu.filter_list.Count.ToString().Length, ' '))"
    $buffer_status = $Host.UI.RawUI.NewBufferCellArray(@("$current$($PSCompletions.config.status_symbol)$($PSCompletions.menu.filter_list.Count)"), $PSCompletions.config.status_text, $PSCompletions.config.status_back)

    $Host.UI.RawUI.SetBufferContents(@{ X = $X; Y = $Y }, $buffer_status)
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod new_tip_buffer {
    param([int]$index)
    if ($PSCompletions.menu.is_show_above) {
        $start = 0
        $line = $PSCompletions.menu.pos.Y
    }
    else {
        $start = $PSCompletions.menu.pos.Y + $PSCompletions.menu.ui_height
        $line = $Host.UI.RawUI.BufferSize.Height - $start
    }
    if ($line -gt 0) {
        $box = @()
        $content = ' ' * $Host.UI.RawUI.BufferSize.Width
        foreach ($_ in 1..$line) {
            $box += $content
        }
        $Host.UI.RawUI.SetBufferContents(
            @{
                X = 0
                Y = $start
            },
            $Host.UI.RawUI.NewBufferCellArray($box, $Host.UI.RawUI.BackgroundColor, $Host.UI.RawUI.BackgroundColor)
        )
    }

    if ($PSCompletions.menu.is_show_tip) {
        if ($PSCompletions.menu.is_show_above) {
            $rest_line = $PSCompletions.menu.cursor_to_top - $PSCompletions.menu.ui_height
        }
        else {
            $rest_line = $PSCompletions.menu.cursor_to_bottom - $PSCompletions.menu.ui_height
        }
        if ($rest_line -le 0) {
            return
        }

        function Get-MultilineTruncatedString {
            param ([string]$inputString)

            $lineWidth = $Host.UI.RawUI.BufferSize.Width

            if ($PSCompletions.config.enable_tip_follow_cursor) {
                $lineWidth -= $Host.UI.RawUI.CursorPosition.X
            }

            $currentWidth = 0
            $outputString = ''
            $currentLine = ''

            $char_record = @{}

            foreach ($char in $inputString.ToCharArray()) {
                if ($char_record.ContainsKey($char)) {
                    $charWidth = $char_record[$char]
                }
                else {
                    $charWidth = $Host.UI.RawUI.NewBufferCellArray($char, $Host.UI.RawUI.BackgroundColor, $Host.UI.RawUI.BackgroundColor).LongLength
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

            return $outputString
        }

        $tip = $PSCompletions.menu.filter_list[$index].ToolTip
        if ($tip -ne $null) {
            $json = $PSCompletions.completions.$($PSCompletions.root_cmd)
            $info = $json.info

            $tip_arr = @()
            foreach ($v in ($PSCompletions.replace_content($tip).Split("`n"))) {
                $tip_arr += (Get-MultilineTruncatedString $v).Split("`n")
            }

            $pos = @{
                X = if ($PSCompletions.config.enable_tip_follow_cursor) { $PSCompletions.menu.pos.X }else { 0 }
                Y = $PSCompletions.menu.pos.Y + $PSCompletions.menu.ui_height + 1
            }
            $full = $rest_line - $tip_arr.Count

            if ($PSCompletions.menu.is_show_above) {
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
                if ($pos.Y -ge $Host.UI.RawUI.BufferSize.Height - 1) {
                    return
                }
            }
            $Host.UI.RawUI.SetBufferContents($pos, $Host.UI.RawUI.NewBufferCellArray($tip_arr, $PSCompletions.config.tip_text, $PSCompletions.config.tip_back))
        }
    }
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod set_selection {
    if ($PSCompletions.menu.old_selection) {
        $Host.UI.RawUI.SetBufferContents($PSCompletions.menu.old_selection.pos, $PSCompletions.menu.old_selection.buffer)
    }

    $X = $PSCompletions.menu.pos.X + 1
    $to_X = $X + $PSCompletions.menu.list_max_width - 1

    # 当前页的第几个
    $Y = $PSCompletions.menu.pos.Y + 1 + $PSCompletions.menu.page_current_index

    # 根据坐标，生成需要被改变内容的矩形，也就是要被选中的项
    $Rectangle = New-Object System.Management.Automation.Host.Rectangle $X, $Y, $to_X, $Y

    # 通过矩形，获取到这个矩形中的原本的内容
    $LineBuffer = $Host.UI.RawUI.GetBufferContents($Rectangle)
    $PSCompletions.menu.old_selection = @{
        pos    = @{
            X = $X
            Y = $Y
        }
        buffer = $LineBuffer
    }
    # 给原本的内容设置前景颜色和背景颜色
    # XXX: 对于多字节字符，需要过滤掉 Trailing 类型字符以确保正确渲染
    # $content = foreach ($i in $LineBuffer) { $i.Character }
    $content = foreach ($i in $LineBuffer.Where({ $_.BufferCellType -ne 'Trailing' })) { $i.Character }
    $LineBuffer = $Host.UI.RawUI.NewBufferCellArray(@([string]::Join('', $content)), $PSCompletions.config.selected_text, $PSCompletions.config.selected_back)
    $Host.UI.RawUI.SetBufferContents(@{ X = $X; Y = $Y }, $LineBuffer)
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod move_selection {
    param([bool]$isDown)

    $moveDirection = if ($isDown) { 1 } else { -1 }

    $is_move = if ($isDown) {
        $PSCompletions.menu.page_current_index -lt $PSCompletions.menu.page_max_index
    }
    else {
        $PSCompletions.menu.page_current_index -gt 0
    }

    $new_selected_index = $PSCompletions.menu.selected_index + $moveDirection

    if ($PSCompletions.config.enable_list_loop) {
        $PSCompletions.menu.selected_index = ($new_selected_index + $PSCompletions.menu.filter_list.Count) % $PSCompletions.menu.filter_list.Count
    }
    else {
        $PSCompletions.menu.selected_index = if ($new_selected_index -lt 0) {
            0
        }
        elseif ($new_selected_index -ge $PSCompletions.menu.filter_list.Count) {
            $PSCompletions.menu.filter_list.Count - 1
        }
        else {
            $new_selected_index
        }
    }

    if ($is_move) {
        $PSCompletions.menu.page_current_index = ($PSCompletions.menu.page_current_index + $moveDirection) % ($PSCompletions.menu.page_max_index + 1)
        if ($PSCompletions.menu.page_current_index -lt 0) {
            $PSCompletions.menu.page_current_index += $PSCompletions.menu.page_max_index + 1
        }
        $PSCompletions.menu.set_selection()
        $PSCompletions.menu.new_status_buffer()
        $PSCompletions.menu.new_tip_buffer($PSCompletions.menu.selected_index)
        $PSCompletions.menu.handle_data('edit')
    }
    elseif ($PSCompletions.config.enable_list_loop -or ($new_selected_index -ge 0 -and $new_selected_index -lt $PSCompletions.menu.filter_list.Count)) {
        if ($isDown) {
            if ($PSCompletions.menu.selected_index -eq 0) {
                $PSCompletions.menu.page_current_index -= $PSCompletions.menu.page_max_index
            }
        }
        else {
            if ($PSCompletions.menu.selected_index -eq $PSCompletions.menu.filter_list.Count - 1) {
                $PSCompletions.menu.page_current_index += $PSCompletions.menu.page_max_index
            }
        }

        $PSCompletions.menu.offset = ($PSCompletions.menu.offset + $moveDirection) % ($PSCompletions.menu.filter_list.Count - $PSCompletions.menu.page_max_index)
        if ($PSCompletions.menu.offset -lt 0) {
            $PSCompletions.menu.offset += $PSCompletions.menu.filter_list.Count - $PSCompletions.menu.page_max_index
        }

        $PSCompletions.menu.old_selection = $null
        $PSCompletions.menu.new_list_buffer($PSCompletions.menu.offset)
        $PSCompletions.menu.set_selection()
        $PSCompletions.menu.new_filter_buffer($PSCompletions.menu.filter)
        $PSCompletions.menu.new_status_buffer()
        $PSCompletions.menu.new_tip_buffer($PSCompletions.menu.selected_index)
        $PSCompletions.menu.handle_data('edit')
    }
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod reset {
    param([bool]$clearAll = $true)
    if ($clearAll) {
        $PSCompletions.menu.data.Clear()
        if ($PSCompletions.menu.origin_full_buffer) {
            $Host.UI.RawUI.SetBufferContents($PSCompletions.menu.origin_full_buffer.top, $PSCompletions.menu.origin_full_buffer.buffer)
            $PSCompletions.menu.origin_full_buffer = $null
        }
    }
    $PSCompletions.menu.old_selection = $null
    $PSCompletions.menu.offset = 0
    $PSCompletions.menu.selected_index = 0
    $PSCompletions.menu.page_current_index = 0
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod handle_data {
    param([string]$Type)

    switch ($Type) {
        add {
            $PSCompletions.menu.data.Add(
                @{
                    page_current_index = $PSCompletions.menu.page_current_index
                    page_max_index     = $PSCompletions.menu.page_max_index
                    selected_index     = $PSCompletions.menu.selected_index
                    offset             = $PSCompletions.menu.offset
                    filter             = $PSCompletions.menu.filter
                    filter_list        = $PSCompletions.menu.filter_list.Clone()
                    old_selection      = $PSCompletions.menu.old_selection.Clone()
                    old_full_buffer    = $PSCompletions.menu.get_buffer($PSCompletions.menu.buffer_start, $PSCompletions.menu.buffer_end)

                    # XXX: 这里必须使用基础类型，否则有可能出现数据不一致，导致菜单塌陷
                    ui_height          = $PSCompletions.menu.ui_height
                    pos_y              = $PSCompletions.menu.pos.Y
                }
            )
        }
        get {
            $data = $PSCompletions.menu.data[-1]
            $PSCompletions.menu.page_current_index = $data.page_current_index
            $PSCompletions.menu.page_max_index = $data.page_max_index
            $PSCompletions.menu.selected_index = $data.selected_index
            $PSCompletions.menu.offset = $data.offset
            $PSCompletions.menu.filter = $data.filter
            $PSCompletions.menu.filter_list = $data.filter_list
            $PSCompletions.menu.old_selection = $data.old_selection

            # XXX: 这里必须使用基础类型，否则有可能出现数据不一致，导致菜单塌陷
            $PSCompletions.menu.ui_height = $data.ui_height
            $PSCompletions.menu.pos.Y = $data.pos_y
        }
        edit {
            $PSCompletions.menu.data[-1] = @{
                page_current_index = $PSCompletions.menu.page_current_index
                page_max_index     = $PSCompletions.menu.page_max_index
                selected_index     = $PSCompletions.menu.selected_index
                offset             = $PSCompletions.menu.offset
                filter             = $PSCompletions.menu.filter
                filter_list        = $PSCompletions.menu.filter_list.Clone()
                old_selection      = $PSCompletions.menu.old_selection.Clone()
                old_full_buffer    = $PSCompletions.menu.get_buffer($PSCompletions.menu.buffer_start, $PSCompletions.menu.buffer_end)

                # XXX: 这里必须使用基础类型，否则有可能出现数据不一致，导致菜单塌陷
                ui_height          = $PSCompletions.menu.ui_height
                pos_y              = $PSCompletions.menu.pos.Y
            }
        }
    }
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod show_module_menu {
    param($filter_list)
    if ($Host.UI.RawUI.BufferSize.Height -lt 5) {
        [Microsoft.PowerShell.PSConsoleReadLine]::UndoAll()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($PSCompletions.info.min_area)
        return ''
    }
    if (!$filter_list) { return '' }

    $suffix = $PSCompletions.config.completion_suffix

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
            if ($PSCompletions.config.enable_path_with_trailing_separator) {
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

    $PSCompletions.menu.pos = @{ X = 0; Y = 0 }

    $PSCompletions.menu.ui_width = 0
    $PSCompletions.menu.ui_height = 0
    $PSCompletions.menu.list_max_width = $PSCompletions.config.list_min_width

    $PSCompletions.menu.filter = ''  # 过滤的关键词

    $PSCompletions.menu.page_current_index = 0 # 当前显示页中的索引

    $PSCompletions.menu.selected_index = 0  # 当前选中项的实际索引

    $PSCompletions.menu.offset = 0  # 索引的偏移量，用于滚动翻页

    # 记录每一次过滤的数据
    $PSCompletions.menu.data = [System.Collections.Generic.List[System.Object]]::new()

    if ($PSCompletions.menu.by_TabExpansion2) {
        $PSCompletions.menu.is_show_tip = $PSCompletions.config.enable_tip_when_enhance
    }
    else {
        $enable_tip = $PSCompletions.config.comp_config.$($PSCompletions.root_cmd).enable_tip
        if ($null -eq $enable_tip) {
            $PSCompletions.menu.is_show_tip = $PSCompletions.config.enable_tip
        }
        else {
            $PSCompletions.menu.is_show_tip = $enable_tip
        }
    }

    $PSCompletions.menu.filter_list = [System.Collections.Generic.List[System.Object]]::new()
    foreach ($item in $filter_list) {
        $PSCompletions.menu.list_max_width = [Math]::Max($PSCompletions.menu.list_max_width, $PSCompletions.menu.get_length($item.ListItemText))
        $PSCompletions.menu.filter_list.Add($item)
    }
    $PSCompletions.menu.ui_width = $PSCompletions.menu.list_max_width + 2

    if ($PSCompletions.config.enable_enter_when_single -and $PSCompletions.menu.filter_list.Count -eq 1) {
        return handleOutput $PSCompletions.menu.filter_list[0]
    }

    $current_encoding = [console]::OutputEncoding
    [console]::OutputEncoding = $PSCompletions.encoding

    $PSCompletions.menu.cursor_to_bottom = $Host.UI.RawUI.BufferSize.Height - $Host.UI.RawUI.CursorPosition.Y - 1
    $PSCompletions.menu.cursor_to_top = $Host.UI.RawUI.CursorPosition.Y - $PSCompletions.config.height_from_menu_bottom_to_cursor_when_above - 1

    $PSCompletions.menu.is_show_above = $PSCompletions.menu.cursor_to_bottom -lt $PSCompletions.menu.cursor_to_top

    if ($PSCompletions.menu.is_show_above) {
        $startY = 0
        $endY = $Host.UI.RawUI.CursorPosition.Y - 1
    }
    else {
        $startY = $Host.UI.RawUI.CursorPosition.Y + 1
        $endY = $Host.UI.RawUI.BufferSize.Height - 1
    }

    $PSCompletions.menu.buffer_start = New-Object System.Management.Automation.Host.Coordinates 0, $startY
    $PSCompletions.menu.buffer_end = New-Object System.Management.Automation.Host.Coordinates ($Host.UI.RawUI.BufferSize.Width - 1), $endY

    $PSCompletions.menu.parse_list()

    # 如果解析后的菜单高度小于 3 (上下边框 + 1个补全项)
    if ($PSCompletions.menu.ui_height -lt 3 -or $PSCompletions.menu.ui_width -gt $Host.ui.RawUI.BufferSize.Width - 2) {
        [Microsoft.PowerShell.PSConsoleReadLine]::UndoAll()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($PSCompletions.info.min_area)
        return ''
    }

    # 显示菜单之前，记录 buffer
    $PSCompletions.menu.origin_full_buffer = $PSCompletions.menu.get_buffer($PSCompletions.menu.buffer_start, $PSCompletions.menu.buffer_end)

    # 显示菜单
    $PSCompletions.menu.new_buffer()
    $PSCompletions.menu.new_list_buffer($PSCompletions.menu.offset)

    $PSCompletions.menu.set_selection()
    $PSCompletions.menu.new_filter_buffer($PSCompletions.menu.filter)
    $PSCompletions.menu.new_status_buffer()
    $PSCompletions.menu.new_tip_buffer($PSCompletions.menu.selected_index)

    $PSCompletions.menu.handle_data('add')

    :loop while (($PressKey = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown,AllowCtrlC')).VirtualKeyCode) {
        $pressShift = 0x10 -band [int]$PressKey.ControlKeyState
        $pressCtrl = $PressKey.ControlKeyState -like '*CtrlPressed*'

        switch ($PressKey.VirtualKeyCode) {
            9 {
                # 9: Tab
                if ($PSCompletions.menu.filter_list.Count -eq 1) {
                    $PSCompletions.menu.reset()
                    handleOutput $PSCompletions.menu.filter_list[$PSCompletions.menu.selected_index]
                    break loop
                }
                $PSCompletions.menu.move_selection(!$pressShift)
                break
            }
            { $_ -eq 27 -or ($pressCtrl -and $_ -eq 67) } {
                # 27: ESC
                # 67: Ctrl + c
                $PSCompletions.menu.reset()
                ''
                break loop
            }
            { $_ -in @(32, 13) } {
                # 32: Space
                # 13: Enter
                handleOutput $PSCompletions.menu.filter_list[$PSCompletions.menu.selected_index]
                $PSCompletions.menu.reset()
                break loop
            }

            # 向上
            # 37: Up
            # 38: Left
            # 85: Ctrl + u
            # 80: Ctrl + p
            # 75: Ctrl + k
            { $_ -in @(37, 38) -or ($pressCtrl -and $_ -in @(85, 80, 75)) } {
                $PSCompletions.menu.move_selection($false)
                break
            }
            # 向下
            # 39: Right
            # 40: Down
            # 68: Ctrl + d
            # 78: Ctrl + n
            # 74: Ctrl + j
            { $_ -in @(39, 40) -or ($pressCtrl -and $_ -in @(68, 78, 74)) } {
                $PSCompletions.menu.move_selection($true)
                break
            }
            # filter character
            { $PressKey.Character } {
                # remove
                if ($PressKey.Character -eq 8) {
                    # 8: Backspace
                    if ($PSCompletions.menu.filter) {
                        $PSCompletions.menu.filter = $PSCompletions.menu.filter.Substring(0, $PSCompletions.menu.filter.Length - 1)
                    }
                    else {
                        $PSCompletions.menu.reset()
                        ''
                        break loop
                    }

                    if ($PSCompletions.menu.data.Count -gt 1) {
                        $old_buffer = $PSCompletions.menu.data[-2].old_full_buffer
                        $Host.UI.RawUI.SetBufferContents($old_buffer.top, $old_buffer.buffer)
                        if ($PSCompletions.menu.data.Count -gt 1) {
                            $PSCompletions.menu.data.RemoveAt($PSCompletions.menu.data.Count - 1)
                        }
                    }
                    else {
                        $old_buffer = $PSCompletions.menu.data[0].old_full_buffer
                        $Host.UI.RawUI.SetBufferContents($old_buffer.top, $old_buffer.buffer)
                        $PSCompletions.menu.data.Clear()
                    }

                    $PSCompletions.menu.handle_data('get')
                }
                else {
                    # add
                    if ($PSCompletions.menu.filter -match '\*$' -and $PressKey.Character -eq '*') {
                        break
                    }
                    $PSCompletions.menu.filter += $PressKey.Character

                    $escapedFilter = $PSCompletions.menu.filter.Replace('[', '`[').Replace(']', '`]')
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
                    foreach ($f in $PSCompletions.menu.filter_list) {
                        if ($f.ListItemText -and $comparison.Invoke($f.ListItemText)) {
                            $resultList.Add($f)
                        }
                    }
                    $PSCompletions.menu.filter_list = $resultList.ToArray()

                    if (!$PSCompletions.menu.filter_list) {
                        $PSCompletions.menu.filter = $PSCompletions.menu.data[-1].filter
                        $PSCompletions.menu.filter_list = $PSCompletions.menu.data[-1].filter_list
                    }
                    else {
                        $PSCompletions.menu.reset($false)
                        $PSCompletions.menu.parse_list()
                        $PSCompletions.menu.new_buffer()
                        $PSCompletions.menu.new_list_buffer($PSCompletions.menu.offset)
                        $PSCompletions.menu.new_tip_buffer($PSCompletions.menu.selected_index)
                        $PSCompletions.menu.new_status_buffer()
                        $PSCompletions.menu.new_filter_buffer($PSCompletions.menu.filter)
                        $PSCompletions.menu.set_selection(0)

                        $PSCompletions.menu.handle_data('add')
                    }
                }
                break
            }
        }
    }
    [console]::OutputEncoding = $current_encoding
}
