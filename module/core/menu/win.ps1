Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod handle_list_first {
    param([array]$filter_list)
    $max_width = 0

    $this.ui_size.width = $this.list_max_width + 2 + $this.config.menu_list_margin_left + $this.config.menu_list_margin_right
    if ($this.is_show_tip) {
        $filterListTasks = @()
        $runspacePool = [runspacefactory]::CreateRunspacePool(1, [Environment]::ProcessorCount)
        $runspacePool.Open()

        $scriptBlock = {
            param ($items, $PSCompletions, $Host_UI)
            function Get-MultilineTruncatedString {
                param ([string]$inputString, $Host_UI = $Host.UI)

                # 指定一行的最大宽度
                $lineWidth = $Host_UI.RawUI.BufferSize.Width

                if ($PSCompletions.config.menu_tip_follow_cursor) {
                    $w = $lineWidth - $Host_UI.RawUI.CursorPosition.X
                    $lineWidth = [Math]::Max($w, $PSCompletions.menu.ui_size.Width)
                }
                $PSCompletions.menu.tip_width = $lineWidth

                # 初始化一些变量
                $currentWidth = 0
                $outputString = ""
                $currentLine = ""

                foreach ($char in $inputString.ToCharArray()) {
                    # 获取当前字符的宽度（1 或 2）
                    $charWidth = if ([System.Text.Encoding]::UTF8.GetByteCount($char) -eq 1) { 1 } else { 2 }

                    # 如果添加这个字符会超过最大宽度，就换行
                    if ($currentWidth + $charWidth -gt $lineWidth) {
                        # 添加当前行到输出字符串并换行
                        $outputString += $currentLine + "`n"
                        # 重置当前行和宽度
                        $currentLine = ""
                        $currentWidth = 0
                    }

                    # 添加字符到当前行，并更新当前宽度
                    $currentLine += $char
                    $currentWidth += $charWidth
                }

                # 添加最后一行到输出字符串
                $outputString += $currentLine

                return $outputString
            }
            function _replace {
                param ($data, $separator = '')
                $data = ($data -join $separator)
                $pattern = '\{\{(.*?(\})*)(?=\}\})\}\}'
                $matches = [regex]::Matches($data, $pattern)
                foreach ($match in $matches) {
                    $data = $data.Replace($match.Value, (Invoke-Expression $match.Groups[1].Value) -join $separator )
                }
                if ($data -match $pattern) { (_replace $data) }else { return $data }
            }

            if ($PSCompletions.current_cmd) {
                $json = $PSCompletions.data.$($PSCompletions.current_cmd)
                $info = $json.info
            }
            foreach ($item in $items) {
                $tip_arr = @()
                if ($item.ToolTip) {
                    $tip = _replace $item.ToolTip
                    foreach ($v in ($tip -split "`n")) {
                        $tip_arr += (Get-MultilineTruncatedString $v $Host_UI) -split "`n"
                    }
                }
                @{
                    ListItemText   = $item.ListItemText
                    CompletionText = $item.CompletionText
                    ToolTip        = $tip_arr
                }
            }
        }

        foreach ($arr in $PSCompletions.split_array($filter_list, [Environment]::ProcessorCount, $true)) {
            $filterListTasks += [powershell]::Create().AddScript($scriptBlock).AddArgument($arr).AddArgument($PSCompletions).AddArgument($Host.UI)
        }

        $runspaces = foreach ($task in $filterListTasks) {
            $task.RunspacePool = $runspacePool
            $job = $task.BeginInvoke()
            @{ Runspace = $task; Job = $job }
        }

        foreach ($rs in $runspaces) {
            $results = $rs.Runspace.EndInvoke($rs.Job)
            $rs.Runspace.Dispose()
            foreach ($result in $results) {
                $this.tip_max_height = [Math]::Max($this.tip_max_height, $result.ToolTip.Count)
                $result = @{
                    ListItemText   = $result.ListItemText
                    CompletionText = $result.CompletionText
                    ToolTip        = $result.ToolTip
                }
                $this.origin_filter_list += $result
                $this.filter_list += $result
            }
        }
        $runspacePool.Close()
        $runspacePool.Dispose()
    }
    else {
        $this.origin_filter_list = [array]$filter_list
        $this.filter_list = [array]$filter_list
    }
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod parse_list {
    # X
    if ($PSCompletions.config.menu_list_follow_cursor) {
        $this.pos.X = $Host.UI.RawUI.CursorPosition.X
        # 如果跟随鼠标，且超过右侧边界，则向左偏移
        $this.pos.X = [Math]::Min($this.pos.X, $Host.UI.RawUI.BufferSize.Width - 1 - $this.ui_size.Width)
    }
    else {
        $this.pos.X = 0
    }

    # 当为 0 时，有几率出现渲染错误，所以坐标右移一点
    if ($this.pos.x -eq 0) { $this.pos.x ++ }

    if ($PSCompletions.config.menu_tip_follow_cursor) {
        $this.pos_tip.X = $this.pos.X
    }
    else {
        $this.pos_tip.X = 0
    }

    # Y
    $this.cursor_to_bottom = $Host.UI.RawUI.BufferSize.Height - $Host.UI.RawUI.CursorPosition.Y - 1
    $this.cursor_to_top = $Host.UI.RawUI.CursorPosition.Y - $PSCompletions.config.menu_above_margin_bottom - 1

    $this.is_show_above = if ($this.cursor_to_bottom -ge $this.cursor_to_top) { $false }else { $true }

    $this.ui_size.height = $this.filter_list.Count + 2
    if ($this.is_show_above) {
        if ($PScompletions.config.menu_above_list_max_count -ne -1) {
            $this.ui_size.height = [Math]::Min($this.ui_size.height, $PScompletions.config.menu_above_list_max_count + 2)
        }
        else {
            $this.ui_size.height = [Math]::Min($this.ui_size.height, $this.cursor_to_top)
        }
    }
    else {
        if ($PScompletions.config.menu_below_list_max_count -ne -1) {
            $this.ui_size.height = [Math]::Min($this.ui_size.height, $PScompletions.config.menu_below_list_max_count + 2)
        }
        else {
            $this.ui_size.height = [Math]::Min($this.ui_size.height, $this.cursor_to_bottom)
        }
    }
    if ($this.is_show_above) {
        $new_ui_height = $this.cursor_to_top - $this.tip_max_height - 1
        if ($new_ui_height -lt 3) {
            $this.is_show_tip = $false
        }
        else {
            $this.ui_size.height = [Math]::Min($new_ui_height, $this.filter_list.Count + 2)
        }
        $this.ui_size.height = [Math]::Max($this.ui_size.height, 3)
        $this.pos.Y = $Host.UI.RawUI.CursorPosition.Y - $this.ui_size.height - $PSCompletions.config.menu_above_margin_bottom
        # 设置 tip 的 起始位置
        $this.pos_tip.Y = $this.pos.Y - $this.tip_max_height - 1
        if ($this.pos_tip.Y -lt 0) {
            $this.is_show_tip = $false
        }
    }
    else {
        $new_ui_height = $this.cursor_to_bottom - $this.tip_max_height - 1
        if ($new_ui_height -lt 3) {
            $this.is_show_tip = $false
        }
        else {
            $this.ui_size.height = [Math]::Min($new_ui_height, $this.filter_list.Count + 2)
        }
        $this.ui_size.height = [Math]::Max($this.ui_size.height, 3)
        $this.pos.Y = $Host.UI.RawUI.CursorPosition.Y + 1
        $this.pos_tip.Y = $this.pos.Y + $this.ui_size.height + 1
        if ($this.pos_tip.Y -ge $Host.UI.RawUI.BufferSize.Height - 1) {
            $this.is_show_tip = $false
        }
    }
    $this.page_max_index = $this.ui_size.height - 3
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
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod get_pos {
    if ($this.is_show_above) {
        $menu_start_pos = @{
            X = $Host.UI.RawUI.WindowPosition.X
            Y = 0
        }
        $menu_end_pos = @{
            X = $this.pos.X + $this.ui_size.Width
            Y = $Host.UI.RawUI.CursorPosition.Y - 1 - $PSCompletions.config.menu_above_margin_bottom
        }
        $menu_start_pos.Y = [Math]::Max($menu_start_pos.Y, $this.pos.Y)
    }
    else {
        $menu_start_pos = $this.pos
        $menu_end_pos = @{
            X = $menu_start_pos.X + $this.ui_size.Width
            Y = $menu_start_pos.Y + $this.ui_size.Height
        }
        $menu_end_pos.Y = [Math]::Min($menu_end_pos.Y, $Host.UI.RawUI.BufferSize.Height - 1)
    }
    if ($this.is_show_tip) {
        $tip_start_pos = @{
            X = $Host.UI.RawUI.WindowPosition.X
            Y = $this.pos.Y - $this.tip_max_height - 1
        }
        if ($this.is_show_above) {
            $tip_end_pos = @{
                X = $Host.UI.RawUI.BufferSize.Width
                Y = $Host.UI.RawUI.CursorPosition.Y - 1 - $PSCompletions.config.menu_above_margin_bottom
            }
            $tip_start_pos.Y = [Math]::Min($tip_start_pos.Y, $Host.UI.RawUI.WindowPosition.Y)
        }
        else {
            $tip_start_pos.Y = $this.pos.Y
            $tip_end_pos = @{
                X = $Host.UI.RawUI.BufferSize.Width
                Y = $tip_start_pos.Y + $this.ui_size.Height + $this.tip_max_height + 1
            }
            $tip_end_pos.Y = [Math]::Min($tip_end_pos.Y, $Host.UI.RawUI.BufferSize.Height - 1)
        }
    }
    @{
        menu = @{
            start_pos = $menu_start_pos
            end_pos   = $menu_end_pos
        }
        tip  = @{
            start_pos = $tip_start_pos
            end_pos   = $tip_end_pos
        }
    }
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod new_cover_buffer {
    if ($PSCompletions.config.menu_tip_cover_buffer) {
        $box = @()
        if ($this.is_show_above) {
            foreach ($_ in 0..($this.pos.Y - 2)) {
                $box += (' ' * $Host.UI.RawUI.BufferSize.Width)
            }
            $pos = $Host.UI.RawUI.WindowPosition
        }
        else {
            foreach ($_ in 0..($Host.UI.RawUI.BufferSize.Height - $this.pos_tip.Y)) {
                $box += (' ' * $Host.UI.RawUI.BufferSize.Width)
            }
            $pos = @{
                X = 0
                Y = $this.pos_tip.Y - 1
            }
            $pos.Y = [Math]::Min($pos.Y, $Host.UI.RawUI.BufferSize.Height - 1)
        }
        $buffer = $Host.UI.RawUI.NewBufferCellArray($box, $host.UI.RawUI.BackgroundColor, $host.UI.RawUI.BackgroundColor)
        $Host.UI.RawUI.SetBufferContents($pos, $buffer)
    }
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod new_buffer {
    if ($PSCompletions.config.menu_list_cover_buffer) {
        $box = @()
        foreach ($_ in 0..$this.ui_size.Height) {
            $box += (' ' * $Host.UI.RawUI.BufferSize.Width)
        }
        $pos = @{
            X = 0
            Y = $this.pos.Y
        }
        if ($this.is_show_above) { $pos.Y -- }
        $buffer = $Host.UI.RawUI.NewBufferCellArray($box, $host.UI.RawUI.BackgroundColor, $host.UI.RawUI.BackgroundColor)
        $Host.UI.RawUI.SetBufferContents($pos, $buffer)
    }

    $border_box = @()
    $content_box = @()
    $line_top = [string]$PSCompletions.config.menu_line_top_left + $PSCompletions.config.menu_line_horizontal * ($this.list_max_width + $PSCompletions.config.menu_list_margin_left + $PSCompletions.config.menu_list_margin_right) + $PSCompletions.config.menu_line_top_right
    $border_box += $line_top
    foreach ($_ in 0..($this.ui_size.height - 3)) {
        $content_length = $this.get_length($this.filter_list[$_].ListItemText)
        $content = $this.filter_list[$_].ListItemText + " " * ($this.list_max_width - $content_length)
        $border_box += [string]$PSCompletions.config.menu_line_vertical + (' ' * ($PSCompletions.config.menu_list_margin_left + $this.list_max_width + $PSCompletions.config.menu_list_margin_right)) + [string]$PSCompletions.config.menu_line_vertical
        $content_box += (' ' * $PSCompletions.config.menu_list_margin_left) + $content + (' ' * $PSCompletions.config.menu_list_margin_right)
    }
    $status = "$(([string]($this.selected_index + 1)).PadLeft($this.filter_list.Count.ToString().Length, ' '))"
    $line_bottom = [string]$PSCompletions.config.menu_line_bottom_left + $PSCompletions.config.menu_line_horizontal * 2 + ' ' * ($status.Length + 1) + $PSCompletions.config.menu_line_horizontal * ($this.list_max_width + $PSCompletions.config.menu_list_margin_left + $PSCompletions.config.menu_list_margin_right - $status.Length - 3) + $PSCompletions.config.menu_line_bottom_right
    $border_box += $line_bottom

    $buffer = $Host.UI.RawUI.NewBufferCellArray($border_box, $PSCompletions.config.menu_color_border_text, $PSCompletions.config.menu_color_border_back)
    $Host.UI.RawUI.SetBufferContents($this.pos, $buffer)

    $buffer = $Host.UI.RawUI.NewBufferCellArray($content_box, $PSCompletions.config.menu_color_item_text, $PSCompletions.config.menu_color_item_back)
    $pos = @{
        X = $this.pos.X + 1
        Y = $this.pos.Y + 1
    }
    $Host.UI.RawUI.SetBufferContents($pos, $buffer)
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod new_list_buffer {
    param([int]$offset)
    $content_box = @()
    foreach ($_ in $offset..($this.ui_size.height - 3 + $offset)) {
        $content_length = $this.get_length($this.filter_list[$_].ListItemText)
        $content = $this.filter_list[$_].ListItemText + " " * ($this.list_max_width - $content_length)
        $content_box += (' ' * $PSCompletions.config.menu_list_margin_left) + $content + (' ' * $PSCompletions.config.menu_list_margin_right)
    }
    $buffer = $Host.UI.RawUI.NewBufferCellArray($content_box, $PSCompletions.config.menu_color_item_text, $PSCompletions.config.menu_color_item_back)
    $pos = @{
        X = $this.pos.X + 1
        Y = $this.pos.Y + 1
    }
    $Host.UI.RawUI.SetBufferContents($pos, $buffer)
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod new_filter_buffer {
    param([string]$filter)
    if ($this.old_filter_buffer) {
        $Host.UI.RawUI.SetBufferContents($this.old_filter_pos, $this.old_filter_buffer)
    }
    $X = $this.pos.X
    $Y = $this.pos.Y

    $old_top = New-Object System.Management.Automation.Host.Coordinates $X, $Y
    $old_bottom = New-Object System.Management.Automation.Host.Coordinates $Host.ui.RawUI.BufferSize.Width, $Y

    $old_buffer = $Host.UI.RawUI.GetBufferContents((New-Object System.Management.Automation.Host.Rectangle $old_top, $old_bottom))

    $this.old_filter_buffer = $old_buffer  # 之前的内容
    $this.old_filter_pos = $old_top  # 之前的位置

    $char = $PSCompletions.config.menu_filter_symbol
    $mindle = [System.Math]::Ceiling($char.Length / 2)
    $start = $char.Substring(0, $mindle)
    $end = $char.Substring($mindle)

    $buffer_filter = $Host.UI.RawUI.NewBufferCellArray(@(@($start, $filter, $end) -join ''), $PSCompletions.config.menu_color_filter_text, $PSCompletions.config.menu_color_filter_back)
    $pos_filter = $Host.UI.RawUI.CursorPosition
    $pos_filter.X = $this.pos.X + 2
    $pos_filter.Y = $this.pos.Y
    $Host.UI.RawUI.SetBufferContents($pos_filter, $buffer_filter)
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod new_status_buffer {
    if ($this.old_status_buffer) {
        $Host.UI.RawUI.SetBufferContents($this.old_status_pos, $this.old_status_buffer)
    }
    $X = $this.pos.X + 3
    if ($this.is_show_above) {
        $Y = $Host.UI.RawUI.CursorPosition.Y - 1 - $PSCompletions.config.menu_above_margin_bottom
    }
    else {
        $Y = $this.pos.Y + $this.ui_size.height - 1
    }

    $old_top = New-Object System.Management.Automation.Host.Coordinates $X, $Y
    $old_bottom = New-Object System.Management.Automation.Host.Coordinates $Host.UI.RawUI.BufferSize.Width, $Y

    $old_buffer = $Host.UI.RawUI.GetBufferContents((New-Object System.Management.Automation.Host.Rectangle $old_top, $old_bottom))

    $this.old_status_buffer = $old_buffer  # 之前的内容
    $this.old_status_pos = $old_top  # 之前的位置

    $current = "$(([string]($this.selected_index + 1)).PadLeft($this.filter_list.Count.ToString().Length, ' '))"
    $buffer_status = $Host.UI.RawUI.NewBufferCellArray(@("$($current)$($PSCompletions.config.menu_status_symbol)$($this.filter_list.Count)"), $PSCompletions.config.menu_color_status_text, $PSCompletions.config.menu_color_status_back)

    $Host.UI.RawUI.SetBufferContents(@{ X = $X; Y = $Y }, $buffer_status)
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod get_old_tip_buffer {
    param([int]$X, [int]$Y)
    if ($PSCompletions.config.menu_tip_cover_buffer) {
        if ($this.is_show_above) {
            $Y = 0
            $to_Y = $this.pos.Y
        }
        else {
            $Y = $this.pos_tip.Y - 1
            $to_Y = $Host.UI.RawUI.BufferSize.Height - 1
        }
    }
    else {
        $Y = $this.pos_tip.Y - 1
        if ($this.is_show_above) {
            $to_Y = $this.pos.Y
        }
        else {
            $to_Y = $this.pos_tip.Y + $this.tip_max_height
        }
    }
    $this.old_tip_buffer = $this.get_buffer(@{ X = 0; Y = $Y }, @{ X = $Host.UI.RawUI.BufferSize.Width; Y = $to_Y })
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod new_tip_buffer {
    param([int]$index)
    $box = @()
    if ($PSCompletions.config.menu_tip_cover_buffer) {
        if ($this.is_show_above) {
            foreach ($_ in 0..($this.pos.Y - 1)) {
                $box += (' ' * $Host.UI.RawUI.BufferSize.Width)
            }
            $pos = @{
                X = 0
                Y = 0
            }
        }
        else {
            foreach ($_ in 0..($Host.UI.RawUI.BufferSize.Height - $this.pos_tip.Y)) {
                $box += (' ' * $Host.UI.RawUI.BufferSize.Width)
            }
            $pos = @{
                X = 0
                Y = $this.pos_tip.Y - 1
            }
        }
    }
    else {
        foreach ($_ in 0..($this.tip_max_height + 1)) {
            $box += (' ' * $Host.UI.RawUI.BufferSize.Width)
        }
        $pos = @{
            X = 0
            Y = $this.pos_tip.Y - 1
        }
        if ($this.is_show_above) {
            $pos.Y = [Math]::Max($pos.Y, 0)
        }
    }
    $buffer = $Host.UI.RawUI.NewBufferCellArray($box, $host.UI.RawUI.BackgroundColor, $host.UI.RawUI.BackgroundColor)
    $Host.UI.RawUI.SetBufferContents($pos, $buffer)

    if ($this.filter_list[$index].ToolTip) {
        $pos = @{
            X = $this.pos_tip.X
            Y = $this.pos_tip.Y
        }
        $buffer = $Host.UI.RawUI.NewBufferCellArray($this.filter_list[$index].ToolTip, $PSCompletions.config.menu_color_tip_text, $PSCompletions.config.menu_color_tip_back)
        $Host.UI.RawUI.SetBufferContents($pos, $buffer)
    }
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod set_selection {
    if ($this.old_selection) {
        $Host.UI.RawUI.SetBufferContents($this.old_selection.pos, $this.old_selection.buffer)
    }

    $X = $this.pos.X + 1
    $to_X = $X + $this.list_max_width - 1
    # 如果高亮需要包含 margin
    if ($PSCompletions.config.menu_selection_with_margin) {
        $to_X += $PSCompletions.config.menu_list_margin_left + $PSCompletions.config.menu_list_margin_right
    }
    else {
        $X += $PSCompletions.config.menu_list_margin_left
    }

    # 当前页的第几个
    $Y = $this.pos.Y + 1 + $this.page_current_index

    # 根据坐标，生成需要被改变内容的矩形，也就是要被选中的项
    $Rectangle = New-Object System.Management.Automation.Host.Rectangle $X, $Y, $to_X, $Y

    # 通过矩形，获取到这个矩形中的原本的内容
    $LineBuffer = $Host.UI.RawUI.GetBufferContents($Rectangle)
    $this.old_selection = @{
        pos    = @{
            X = $X
            Y = $Y
        }
        buffer = $LineBuffer
    }
    # 给原本的内容设置颜色和背景颜色
    # 对于多字节字符，会过滤掉 Trailing 类型字符以确保正确渲染
    $content = foreach ($i in $LineBuffer.Where({ $_.BufferCellType -ne "Trailing" })) { $i.Character }
    $LineBuffer = $Host.UI.RawUI.NewBufferCellArray(
        @([string]::Join('', $content)),
        $PSCompletions.config.menu_color_selected_text,
        $PSCompletions.config.menu_color_selected_back
    )
    $Host.UI.RawUI.SetBufferContents(@{ X = $X; Y = $Y }, $LineBuffer)
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod move_selection {
    param([bool]$isDown)

    $moveDirection = if ($isDown) { 1 } else { -1 }

    $is_move = if ($isDown) {
        $this.page_current_index -lt $this.page_max_index
    }
    else {
        $this.page_current_index -gt 0
    }

    $new_selected_index = $this.selected_index + $moveDirection

    if ($PSCompletions.config.menu_is_loop) {
        $this.selected_index = ($new_selected_index + $this.filter_list.Count) % $this.filter_list.Count
    }
    else {
        # Handle no loop
        $this.selected_index = if ($new_selected_index -lt 0) {
            0
        }
        elseif ($new_selected_index -ge $this.filter_list.Count) {
            $this.filter_list.Count - 1
        }
        else {
            $new_selected_index
        }
    }

    if ($is_move) {
        $this.page_current_index = ($this.page_current_index + $moveDirection) % ($this.page_max_index + 1)
        if ($this.page_current_index -lt 0) {
            $this.page_current_index += $this.page_max_index + 1
        }
    }
    elseif ($PSCompletions.config.menu_is_loop -or ($new_selected_index -ge 0 -and $new_selected_index -lt $this.filter_list.Count)) {
        if (!$isDown -and $this.selected_index -eq $this.filter_list.Count - 1) {
            $this.page_current_index += $this.page_max_index
        }
        elseif ($isDown -and $this.selected_index -eq 0) {
            $this.page_current_index -= $this.page_max_index
        }

        $this.offset = ($this.offset + $moveDirection) % ($this.filter_list.Count - $this.page_max_index)
        if ($this.offset -lt 0) {
            $this.offset += $this.filter_list.Count - $this.page_max_index
        }

        $this.new_list_buffer($this.offset)
        $this.old_selection = $null
    }
    $this.set_selection()
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod get_prefix {
    $prefix = $this.filter_list[-1].CompletionText
    for ($i = $this.filter_list.count - 2; $i -ge 0 -and $prefix; --$i) {
        $text = $this.filter_list[$i].CompletionText
        if ($text) {
            while ($prefix -and !$text.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
                $prefix = $prefix.Substring(0, $prefix.Length - 1)
            }
        }
    }
    $this.filter = $this.filter_by_auto_pick = $prefix
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod filter_completions {
    param([array]$filter_list)
    # 如果是前缀匹配
    if ($PSCompletions.config.menu_is_prefix_match) {
        $match = "$($this.filter)*"
    }
    else {
        $match = "*$($this.filter)*"
    }
    $this.filter_list = @()

    foreach ($f in $filter_list) {
        if ($f.CompletionText -and $f.CompletionText -like $match) {
            $this.filter_list += $f
        }
    }
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod reset {
    param([bool]$clearAll, [bool]$is_menu_enhance)
    # reset content

    if ($this.old_tip_buffer) {
        $Host.UI.RawUI.SetBufferContents($this.old_tip_buffer.top, $this.old_tip_buffer.buffer)
    }

    if ($this.old_menu_buffer) {
        $Host.UI.RawUI.SetBufferContents($this.old_menu_buffer.top, $this.old_menu_buffer.buffer)
    }

    if ($clearAll) {
        $this.old_tip_buffer = $null
        $this.old_menu_buffer = $null
        if ($this.origin_menu_buffer) {
            $Host.UI.RawUI.SetBufferContents($this.origin_menu_buffer.top, $this.origin_menu_buffer.buffer)
            $this.origin_menu_buffer = $null
        }
        if ($this.origin_tip_buffer) {
            $Host.UI.RawUI.SetBufferContents($this.origin_tip_buffer.top, $this.origin_tip_buffer.buffer)
            $this.origin_tip_buffer = $null
        }
    }
    $this.old_selection = $null
    $this.old_filter_buffer = $null
    $this.old_filter_pos = $null
    $this.old_status_buffer = $null
    $this.old_status_pos = $null

    $this.offset = 0
    $this.selected_index = 0
    $this.page_current_index = 0
    $this.tip_max_height = 0

    if ($is_menu_enhance) {
        $this.is_show_tip = $PSCompletions.config.menu_show_tip_when_enhance -eq 1
    }
    else {
        if ($PSCompletions.current_cmd) {
            $menu_show_tip = $PSCompletions.config.comp_config.$($PSCompletions.current_cmd).menu_show_tip
            if ($menu_show_tip -ne $null) {
                $this.is_show_tip = $menu_show_tip -eq 1
            }
            else {
                $this.is_show_tip = $PSCompletions.config.menu_show_tip -eq 1
            }
        }
        else {
            $this.is_show_tip = $PSCompletions.config.menu_show_tip -eq 1
        }
    }
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod show_module_menu {
    param([array]$filter_list, [bool]$is_menu_enhance)

    if (!$filter_list) { return }

    $lastest_encoding = [console]::OutputEncoding
    [console]::OutputEncoding = $PSCompletions.encoding

    $this.pos = @{ X = 0; Y = 0 }
    $this.pos_tip = @{ X = 0; Y = 0 }
    $this.list_max_width = [Math]::Max($this.list_max_width, $PSCompletions.config.menu_list_min_width)

    $this.ui_size = $Host.UI.RawUI.BufferSize

    $this.filter = ''  # 过滤的关键词
    $this.old_filter = ''

    $this.page_current_index = 0 # 当前显示第几个

    $this.selected_index = 0  # 当前选中的索引
    $this.old_selected_index = 0

    $this.offset = 0  # 索引的偏移量，用于滚动翻页

    $this.reset($true, $is_menu_enhance)

    $this.origin_filter_list = @()
    $this.filter_list = @()
    $this.handle_list_first($filter_list)

    if ($PSCompletions.config.enter_when_single -and $this.filter_list.Count -eq 1) {
        return $this.filter_list[$this.selected_index].CompletionText
    }
    $this.parse_list()

    # 如果解析后的菜单高度小于 3 (上下边框 + 1个补全项)
    if ($this.ui_size.Height -lt 3 -or $this.ui_size.Width -gt $Host.ui.RawUI.BufferSize.Width - 2) {
        [Microsoft.PowerShell.PSConsoleReadLine]::UndoAll()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($PSCompletions.info.min_area)
        ''
        return
    }

    # 显示菜单之前，记录 buffer
    $pos = $this.get_pos()
    $this.origin_menu_buffer = $this.get_buffer($pos.menu.start_pos, $pos.menu.end_pos)

    $this.origin_tip_buffer = $this.get_buffer($pos.tip.start_pos, $pos.tip.end_pos)

    $this.old_menu_buffer = $this.get_buffer(
        @{
            X = $Host.UI.RawUI.WindowPosition.X
            Y = $this.pos.Y
        },
        @{
            X = $Host.ui.RawUI.BufferSize.Width
            Y = $this.pos.Y + $this.ui_size.height - 1
        })

    if ($this.is_show_tip) { $this.get_old_tip_buffer($this.pos_tip.X, $this.pos_tip.Y) }
    # 显示菜单
    $this.new_buffer()
    if ($this.is_show_tip) { $this.new_tip_buffer($this.selected_index) }
    if ($PSCompletions.config.menu_is_prefix_match) { $this.get_prefix() }
    $this.new_filter_buffer($this.filter)
    $this.new_status_buffer()
    $this.set_selection()
    :loop while (($PressKey = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown,AllowCtrlC')).VirtualKeyCode) {
        $shift_pressed = 0x10 -band [int]$PressKey.ControlKeyState
        if ($PressKey.ControlKeyState -like "*CtrlPressed*") {
            switch ($PressKey.VirtualKeyCode) {
                67 {
                    # 67: Ctrl + c
                    $this.reset($true)
                    ''
                    break loop
                }
                { $_ -eq 85 -or $_ -eq 80 } {
                    # 85: Ctrl + u
                    # 80: Ctrl + p
                    $this.move_selection($false)
                    break
                }

                { $_ -eq 68 -or $_ -eq 78 } {
                    # 68: Ctrl + d
                    # 78: Ctrl + n
                    $this.move_selection($true)
                    break
                }
            }
        }
        switch ($PressKey.VirtualKeyCode) {
            { $_ -in @(9, 32) } {
                # 9: Tab
                # 32: Space
                if ($this.filter_list.Count -eq 1) {
                    $this.reset($true)
                    $this.filter_list[$this.selected_index].CompletionText
                    break loop
                }
                if ($shift_pressed) {
                    # Up
                    $this.move_selection($false)
                }
                else {
                    # Down
                    $this.move_selection($true)
                }
                break
            }
            27 {
                # 27: ESC
                $this.reset($true)
                ''
                break loop
            }
            13 {
                # 13: Enter
                $this.filter_list[$this.selected_index].CompletionText
                $this.reset($true)
                break loop
            }

            # 向上
            # 37: Up
            # 38: Left
            { $_ -in @(37, 38) } {
                $this.move_selection($false)
                break
            }
            # 向下
            # 39: Right
            # 40: Down
            { $_ -in @(39, 40) } {
                $this.move_selection($true)
                break
            }
            # Character/Backspace
            { $PressKey.Character } {
                # update filter
                if ($PressKey.Character -eq 8) {
                    # 8: backspace
                    if ($this.filter -eq $this.filter_by_auto_pick) {
                        $this.filter = ''
                        $this.filter_by_auto_pick = ''
                        $this.reset($true)
                        ''
                        break loop
                    }
                    if ($this.filter) {
                        $this.filter = $this.filter.Substring(0, $this.filter.Length - 1)
                    }
                    else {
                        $this.reset($true)
                        ''
                        break loop
                    }
                    $this.new_cover_buffer()
                    $this.reset()
                    $this.filter_completions($this.origin_filter_list)
                    foreach ($item in $this.filter_list) {
                        $this.tip_max_height = [Math]::Max($this.tip_max_height, $item.ToolTip.Count)
                    }
                    $this.parse_list()
                    $this.new_buffer()
                    if ($this.is_show_tip) { $this.new_tip_buffer($this.selected_index) }
                    $this.new_status_buffer()
                    $this.set_selection(0)
                }
                else {
                    # add char
                    $this.filter += $PressKey.Character
                    $this.filter_completions($this.filter_list)
                    if (!$this.filter_list) {
                        $this.filter = $this.old_filter
                        $this.filter_list = $old_filter_list
                    }
                    else {
                        $this.new_cover_buffer()
                        $this.reset()
                        foreach ($item in $this.filter_list) {
                            $this.tip_max_height = [Math]::Max($this.tip_max_height, $item.ToolTip.Count)
                        }

                        $this.parse_list()
                        $this.new_buffer()
                        if ($this.is_show_tip) { $this.new_tip_buffer($this.selected_index) }
                        $this.new_status_buffer()
                        $this.set_selection(0)
                    }
                }
                break
            }
        }
        if ($this.selected_index -ne $this.old_selected_index) {
            $this.new_status_buffer()
            if ($this.is_show_tip) { $this.new_tip_buffer($this.selected_index) }
            $this.old_selected_index = $this.selected_index
        }
        if ($this.filter -ne $this.old_filter) {
            $this.new_filter_buffer($this.filter)
            $this.old_filter = $this.filter
            $old_filter_list = $this.filter_list
        }
    }
    [console]::OutputEncoding = $lastest_encoding
    $this.list_max_width = 0
}
