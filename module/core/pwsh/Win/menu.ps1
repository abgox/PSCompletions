Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod handle_list {
    if ($this.is_show_tip) {
        $max_width = 0
        $tip_max_height = 0
        $this.filter_list = $this.filter_list | ForEach-Object {
            $symbol = ($_.symbol | ForEach-Object { $PSCompletions.config."symbol_$($_)" }) -join ''
            $pad = if ($symbol) { "$($PSCompletions.config.menu_between_item_and_symbol)$($symbol)" }else { '' }
            $name_with_symbol = "$($_.name[-1])$($pad)"

            $width = $this.get_length($name_with_symbol)
            if ($width -gt $max_width) { $max_width = $width }
            $json = $PSCompletions.data.$($PSCompletions.current_cmd)
            $info = $json.info

            if ($_.tip) {
                $tip = $PSCompletions.replace_content($_.tip)
                $tip_arr = $tip -split "`n"
            }
            else {
                $tip = ' '
                $tip_arr = @()
            }
            if ($tip_arr.Count -gt $tip_max_height) { $tip_max_height = $tip_arr.Count }
            @{
                name  = $name_with_symbol
                value = $_.name[-1]
                width = $width
                tip   = $tip
            }
        }
        if ($max_width -lt $PSCompletions.config.menu_list_min_width) {
            $max_width = $PSCompletions.config.menu_list_min_width
        }
        $this.list_max_width = $max_width
        $this.tip_max_height = $tip_max_height

        $this.filter_list | ForEach-Object {
            $pad = $max_width - $_.width
            $_.name = "$($_.name)$(' ' * $pad)"
        }

        if ($this.filter_list -is [array]) {
            $PSCompletions.is_single = $false
        }
        else {
            $PSCompletions.is_single = $true
            $this.filter_list = @($this.filter_list)
        }
        $this.ui_size.Width = 1 + $PSCompletions.config.menu_list_margin_left + $max_width + $PSCompletions.config.menu_list_margin_right + 1
    }
    else {
        $max_width = 0
        $this.filter_list = $this.filter_list | ForEach-Object {
            $symbol = ($PSCompletions.replace_content($_.symbol, ' ') -split ' ' | ForEach-Object { $PSCompletions.config."symbol_$($_)" }) -join ''
            $pad = if ($symbol) { "$($PSCompletions.config.menu_between_item_and_symbol)$($symbol)" }else { '' }
            $name_with_symbol = "$($_.name[-1])$($pad)"

            $width = $this.get_length($name_with_symbol)
            if ($width -gt $max_width) {
                $max_width = $width
            }
            @{
                name  = $name_with_symbol
                value = $_.name[-1]
                width = $width
            }
        }

        if ($max_width -lt $PSCompletions.config.menu_list_min_width) {
            $max_width = $PSCompletions.config.menu_list_min_width
        }
        $this.list_max_width = $max_width

        $this.filter_list | ForEach-Object {
            $pad = $max_width - $_.width
            $_.name = "$($_.name)$(' ' * $pad)"
        }

        if ($this.filter_list -is [array]) {
            $PSCompletions.is_single = $false
        }
        else {
            $PSCompletions.is_single = $true
            $this.filter_list = @($this.filter_list)
        }
        $this.ui_size.Width = 1 + $PSCompletions.config.menu_list_margin_left + $max_width + $PSCompletions.config.menu_list_margin_right + 1
    }
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod parse_list {
    # X
    if ($PSCompletions.config.menu_list_follow_cursor) {
        $this.pos.X = $Host.UI.RawUI.CursorPosition.X
        # 如果跟随鼠标，如果在超过右侧边界，则向左偏移
        if ($this.pos.X + $this.ui_size.Width -gt $Host.UI.RawUI.BufferSize.Width - 1) {
            $this.pos.X = $Host.UI.RawUI.BufferSize.Width - 1 - $this.ui_size.Width
        }
    }
    else {
        $this.pos.X = 0
    }
    $this.pos_tip.X = if ($PSCompletions.config.menu_tip_follow_cursor) { $this.pos.X }else { 0 }

    # 当为 0 时，有几率出现渲染错误，所以坐标右移一点
    if ($this.pos.x -eq 0) { $this.pos.x ++ }

    # Y
    $this.cursor_to_bottom = $Host.UI.RawUI.BufferSize.Height - $Host.UI.RawUI.CursorPosition.Y - 1
    $this.cursor_to_top = $Host.UI.RawUI.CursorPosition.Y - $PSCompletions.config.menu_above_margin_bottom - 1

    $this.is_show_above = if ($this.cursor_to_bottom -ge $this.cursor_to_top) { $false }else { $true }

    $this.ui_size.height = $this.filter_list.Count + 2
    if ($this.is_show_above) {
        if ($PScompletions.config.menu_above_list_max_count -ne -1) {
            if ($this.filter_list.Count -gt $PScompletions.config.menu_above_list_max_count) {
                $this.ui_size.height = $PScompletions.config.menu_above_list_max_count + 2
            }
        }
        if ($this.ui_size.height -gt $this.cursor_to_top) {
            $this.ui_size.height = $this.cursor_to_top
        }
    }
    else {
        if ($PScompletions.config.menu_below_list_max_count -ne -1) {
            if ($this.filter_list.Count -gt $PScompletions.config.menu_below_list_max_count) {
                $this.ui_size.height = $PScompletions.config.menu_below_list_max_count + 2
            }
        }
        if ($this.ui_size.height -gt $this.cursor_to_bottom) {
            $this.ui_size.height = $this.cursor_to_bottom
        }
    }
    if ($this.is_show_above) {
        $usable_height = $this.cursor_to_top - $this.ui_size.height

        if ($this.tip_max_height -ge $usable_height) {
            $new_ui_height = $this.ui_size.height - ($this.tip_max_height - $usable_height) - 1
            if ($new_ui_height -lt 3) {
                $this.is_show_tip = $false
            }
            else {
                $this.ui_size.height = $new_ui_height
            }
        }
        $this.pos.Y = $Host.UI.RawUI.CursorPosition.Y - $this.ui_size.height - $PSCompletions.config.menu_above_margin_bottom
        # 设置 tip 的 起始位置
        $this.pos_tip.Y = $this.pos.Y - $this.tip_max_height - 1
        if ($this.pos_tip.Y -lt 0) {
            $this.is_show_tip = $false
        }
    }
    else {
        $usable_height = $this.cursor_to_bottom - $this.ui_size.Height

        if ($this.tip_max_height -ge $usable_height) {
            $new_ui_height = $this.ui_size.height - ($this.tip_max_height - $usable_height) - 1
            if ($new_ui_height -lt 3) {
                $this.is_show_tip = $false
            }
            else {
                $need_height = $this.pos.Y + $new_ui_height + 1 + $this.tip_max_height
                if ($need_height -ge $Host.UI.RawUI.BufferSize.Height) {
                    $this.is_show_tip = $false
                }
                else {
                    $this.ui_size.height = $new_ui_height
                    $this.pos_tip.Y = $this.pos.Y + $new_ui_height + 1
                }
            }
        }
        $this.pos.Y = $Host.UI.RawUI.CursorPosition.Y + 1
        $this.pos_tip.Y = $this.pos.Y + $this.ui_size.height + 1
    }
    $this.page_max_index = $this.ui_size.height - 3
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod get_old_buffer {
    param($X = $this.pos.X, $Y = $this.pos.Y)
    $old_top = New-Object System.Management.Automation.Host.Coordinates 0, $Y
    $old_bottom = New-Object System.Management.Automation.Host.Coordinates $Host.ui.RawUI.BufferSize.Width, ($Y + $this.ui_size.height)
    $old_buffer = $Host.UI.RawUI.GetBufferContents((New-Object System.Management.Automation.Host.Rectangle $old_top, $old_bottom))
    $this.old_menu_buffer = $old_buffer  # 之前的内容
    $this.old_menu_pos = $old_top  # 之前的位置
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod new_buffer {
    param($offset = 0)

    if ($PSCompletions.config.menu_list_cover_buffer) {
        $box = @()
        0..$this.ui_size.Height | ForEach-Object {
            $box += (' ' * $Host.UI.RawUI.BufferSize.Width)
        }
        $pos = @{
            X = 0
            Y = $this.pos.Y
        }
        if ($PSCompletions.menu.is_show_above) { $pos.Y -- }
        $buffer = $Host.UI.RawUI.NewBufferCellArray($box, $host.UI.RawUI.BackgroundColor, $host.UI.RawUI.BackgroundColor)
        $Host.UI.RawUI.SetBufferContents($pos, $buffer)
    }

    $border_box = @()
    $content_box = @()
    $line_top = [string]$PSCompletions.config.menu_line_top_left + $PSCompletions.config.menu_line_horizontal * ($this.list_max_width + $PSCompletions.config.menu_list_margin_left + $PSCompletions.config.menu_list_margin_right) + $PSCompletions.config.menu_line_top_right
    $border_box += $line_top
    $offset..($this.ui_size.height - 3 + $offset) | ForEach-Object {
        $content = $this.filter_list[$_].name
        $border_box += [string]$PSCompletions.config.menu_line_vertical + (' ' * ($PSCompletions.config.menu_list_margin_left + $content.Length + $PSCompletions.config.menu_list_margin_right)) + [string]$PSCompletions.config.menu_line_vertical
        $content_box += (' ' * $PSCompletions.config.menu_list_margin_left) + $content + (' ' * $PSCompletions.config.menu_list_margin_right)
    }
    $line_bottom = [string]$PSCompletions.config.menu_line_bottom_left + $PSCompletions.config.menu_line_horizontal * ($this.list_max_width + $PSCompletions.config.menu_list_margin_left + $PSCompletions.config.menu_list_margin_right) + $PSCompletions.config.menu_line_bottom_right
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
    param($offset = 0)
    $content_box = @()
    $offset..($this.ui_size.height - 3 + $offset) | ForEach-Object {
        $content = $this.filter_list[$_].name
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
    param($filter)
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
    param($current = 1)
    if ($this.old_status_buffer) {
        $Host.UI.RawUI.SetBufferContents($this.old_status_pos, $this.old_status_buffer)
    }
    $X = $this.pos.X
    $Y = $this.pos.Y + $this.ui_size.height - 1

    $old_top = New-Object System.Management.Automation.Host.Coordinates $X, $Y
    $old_bottom = New-Object System.Management.Automation.Host.Coordinates $Host.ui.RawUI.BufferSize.Width, ($Y + 1)

    $old_buffer = $Host.UI.RawUI.GetBufferContents((New-Object System.Management.Automation.Host.Rectangle $old_top, $old_bottom))

    $this.old_status_buffer = $old_buffer  # 之前的内容
    $this.old_status_pos = $old_top  # 之前的位置

    $current = " $(([string]($this.selected_index + 1)).PadLeft($this.filter_list.Count.ToString().Length, ' '))"
    $buffer_status = $Host.UI.RawUI.NewBufferCellArray(@("$($current) $($PSCompletions.config.menu_status_symbol) $($PSCompletions.menu.filter_list.Count) "), $PSCompletions.config.menu_color_status_text, $PSCompletions.config.menu_color_status_back)

    $pos_status = $Host.UI.RawUI.CursorPosition
    $pos_status.X = $this.pos.X + 2
    $pos_status.Y = $this.pos.Y + $this.ui_size.height - 1
    $Host.UI.RawUI.SetBufferContents($pos_status, $buffer_status)
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod get_old_tip_buffer {
    param($X = $this.pos_tip.X, $Y = $this.pos_tip.Y)
    if ($PSCompletions.config.menu_tip_cover_buffer) {
        if ($PSCompletions.menu.is_show_above) {
            $Y = 0
            $to_Y = $this.pos.Y
        }
        else {
            $Y = $this.pos_tip.Y - 1
            $to_Y = $Host.UI.RawUI.BufferSize.Height
        }
    }
    else {
        if ($PSCompletions.menu.is_show_above) {
            $Y = $this.pos_tip.Y - 1
            $to_Y = $this.pos.Y
        }
        else {
            $Y = $this.pos_tip.Y - 1
            $to_Y = $this.pos_tip.Y + $this.tip_max_height
        }
    }
    $old_top = New-Object System.Management.Automation.Host.Coordinates 0, $Y
    $old_bottom = New-Object System.Management.Automation.Host.Coordinates $Host.ui.RawUI.BufferSize.Width, $to_Y

    $old_buffer = $Host.UI.RawUI.GetBufferContents((New-Object System.Management.Automation.Host.Rectangle $old_top, $old_bottom))
    $this.old_tip_buffer = $old_buffer
    $this.old_tip_pos = $old_top
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod new_tip_buffer {
    param($index = 0)
    $box = @()

    if ($PSCompletions.config.menu_tip_cover_buffer) {
        if ($PSCompletions.menu.is_show_above) {
            0..($this.pos.Y - 1) | ForEach-Object {
                $box += (' ' * $Host.UI.RawUI.BufferSize.Width)
            }
            $pos = @{
                X = 0
                Y = 0
            }
        }
        else {
            0..($Host.UI.RawUI.BufferSize.Height - $this.pos_tip.Y) | ForEach-Object {
                $box += (' ' * $Host.UI.RawUI.BufferSize.Width)
            }
            $pos = @{
                X = 0
                Y = $this.pos_tip.Y - 1
            }
        }
    }
    else {
        0..($this.tip_max_height + 1) | ForEach-Object {
            $box += (' ' * $Host.UI.RawUI.BufferSize.Width)
        }
        $pos = @{
            X = 0
            Y = $this.pos_tip.Y - 1
        }
        if ($PSCompletions.menu.is_show_above -and $pos.Y -lt 0) { $pos.Y = 0 }
    }
    $buffer = $Host.UI.RawUI.NewBufferCellArray($box, $host.UI.RawUI.BackgroundColor, $host.UI.RawUI.BackgroundColor)
    $Host.UI.RawUI.SetBufferContents($pos, $buffer)

    $box = @()
    function _do($string, $max_width, $is_cut) {
        $width = $this.get_length($string)
        if ($is_cut) {
            if ($width -le $max_width - 3) {
                return "$($string)..."
            }
        }
        else {
            if ($width -le $max_width) {
                return $string
            }
        }
        _do $string.Substring(0, ($string.Length - 2)) $max_width $true
    }

    $this.filter_list[$index].tip -split "`n" | ForEach-Object {
        if ($_) { $box += _do $_ ($Host.UI.RawUI.BufferSize.Width - 1) }
    }
    if ($box) {
        $pos = @{
            X = $this.pos_tip.X
            Y = $this.pos_tip.Y
        }
        $buffer = $Host.UI.RawUI.NewBufferCellArray($box, $PSCompletions.config.menu_color_tip_text, $PSCompletions.config.menu_color_tip_back)
        $Host.UI.RawUI.SetBufferContents($pos, $buffer)
    }
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod set_selection {
    param($offset = $this.page_current_index)
    if ($this.old_selection) {
        $Host.UI.RawUI.SetBufferContents($this.old_selection.pos, $this.old_selection.buffer)
    }
    # 如果高亮需要包含 margin
    if ($PSCompletions.config.menu_selection_with_margin) {
        $X = $this.pos.X + 1
        $to_X = $X + $this.list_max_width - 1 + $PSCompletions.config.menu_list_margin_left + $PSCompletions.config.menu_list_margin_right
    }
    else {
        $X = $this.pos.X + 1 + $PSCompletions.config.menu_list_margin_left
        $to_X = $X + $this.list_max_width - 1
    }

    # 当前页的第几个
    $Y = $this.pos.Y + 1 + $offset

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
    $LineBuffer = $Host.UI.RawUI.NewBufferCellArray(
        @([string]::Join('', ($LineBuffer | .{ process { $_.Character } }))),
        $PSCompletions.config.menu_color_selected_text,
        $PSCompletions.config.menu_color_selected_back
    )
    $Host.UI.RawUI.SetBufferContents(@{ X = $X; Y = $Y }, $LineBuffer)
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod move_selection {
    param([int]$count)
    $is_scroll = $false
    $is_move = $false
    if ($this.selected_index + $count -ge 0 -and $this.selected_index + $count -le ($this.filter_list.Count - 1) ) {
        if ($count -gt 0) {
            if ($this.page_current_index -ge $this.page_max_index) {
                $is_scroll = $true
            }
            else {
                $is_move = $true
            }
        }
        else {
            if ($this.page_current_index -le 0) {
                $is_scroll = $true
            }
            else {
                $is_move = $true
            }
        }
    }

    if ($is_move) {
        $this.page_current_index += $count
        $this.selected_index += $count
        $this.set_selection()
    }
    if ($is_scroll) {
        $this.selected_index += $count
        $this.offset += $count
        $this.new_list_buffer($this.offset)

        # 处理当前选中的行
        $box = @()
        $content = $this.filter_list[$this.ui_size.height - 3 + $this.offset].name
        $box += (' ' * $PSCompletions.config.menu_list_margin_left) + $content + (' ' * $PSCompletions.config.menu_list_margin_right)
        $buffer = $Host.UI.RawUI.NewBufferCellArray($box, $PSCompletions.config.menu_color_item_text, $PSCompletions.config.menu_color_item_back)
        $pos = @{
            X = $this.pos.X + 1
            Y = $this.pos.Y + $this.ui_size.height - 1
        }
        $Host.UI.RawUI.SetBufferContents($pos, $buffer)
        $this.old_selection = $null
        $this.set_selection()
    }
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod get_prefix {
    $prefix = $this.filter_list[-1].value
    for ($i = $this.filter_list.count - 2; $i -ge 0 -and $prefix; --$i) {
        $text = $this.filter_list[$i].value
        if ($text) {
            while ($prefix -and !$text.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
                $prefix = $prefix.Substring(0, $prefix.Length - 1)
            }
        }
    }
    $this.filter = $this.filter_by_auto_pick = $prefix
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod filter_completions {
    param($filter_list)
    # 如果是前缀匹配
    if ($PSCompletions.config.menu_is_prefix_match) {
        $match = "$($this.filter)*"
    }
    else {
        $match = "*$($this.filter)*"
    }
    $this.filter_list = $filter_list | Where-Object { $_.name -like $match } | Where-Object { $_.name -ne '' }
    if ($this.filter_list -is [array]) {
        $PSCompletions.is_single = $false
    }
    else {
        $PSCompletions.is_single = $true
        $this.filter_list = @($this.filter_list)
    }
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod reset {
    param($clearAll)
    # reset content
    try {
        $Host.UI.RawUI.SetBufferContents($this.old_tip_pos, $this.old_tip_buffer)
        if ($clearAll) {
            $this.old_tip_buffer = $null
            $this.old_tip_pos = $null
        }
    }
    catch {}
    try {
        $Host.UI.RawUI.SetBufferContents($this.old_menu_pos, $this.old_menu_buffer)
        if ($clearAll) {
            $this.old_menu_buffer = $null
            $this.old_menu_pos = $null
        }
    }
    catch {}
    $this.old_selection = $null
    $this.old_filter_buffer = $null
    $this.old_filter_pos = $null
    $this.old_status_buffer = $null
    $this.old_status_pos = $null

    $this.offset = 0
    $this.selected_index = 0
    $this.page_current_index = 0

    $menu_show_tip = $PSCompletions.config.comp_config.$($PSCompletions.current_cmd).menu_show_tip
    if ($menu_show_tip) {
        $this.is_show_tip = $menu_show_tip -eq 1
    }
    else {
        $this.is_show_tip = $PSCompletions.config.menu_show_tip -eq 1
    }
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod show_module_menu {
    param($filter_list)
    $this.origin_filter_list = $this.filter_list = $filter_list

    $this.pos = $Host.UI.RawUI.WindowPosition
    $this.pos_tip = $Host.UI.RawUI.WindowPosition
    $this.list_max_width = 0

    $this.ui_size = $Host.UI.RawUI.BufferSize

    $this.filter = ''  # 过滤的关键词

    $this.page_current_index = 0 # 当前显示第几个

    $this.selected_index = 0  # 当前选中的索引

    $this.offset = 0  # 索引的偏移量，用于滚动翻页

    $this.filter_completions($this.origin_filter_list)
    # 如果没有可用的选项，直接结束，触发路径补全
    if (!$this.filter_list) { return }
    $this.handle_list()

    if ($PSCompletions.config.enter_when_single -and $PSCompletions.is_single) {
        return $this.filter_list[$this.selected_index].value
    }
    $this.parse_list()

    # 如果解析后的菜单高度小于 3 (上下边框 + 1个补全项)
    if ($this.ui_size.Height -lt 3 -or $this.ui_size.Width -gt $Host.ui.RawUI.BufferSize.Width - 2) {
        [Microsoft.PowerShell.PSConsoleReadLine]::UndoAll()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($PSCompletions.info.min_area)
        ''
        return
    }

    # 第一次显示菜单之前，记录之前的 buffer 内容
    $this.get_old_buffer()
    if ($this.is_show_tip) { $this.get_old_tip_buffer() }
    # 显示菜单
    $this.new_buffer($this.offset)
    if ($this.is_show_tip) { $this.new_tip_buffer($this.selected_index) }
    if ($PSCompletions.config.menu_is_prefix_match) { $this.get_prefix() }
    $this.new_filter_buffer($this.filter)
    $this.new_status_buffer()
    $this.set_selection()

    try {
        :loop while (($PressKey = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown,AllowCtrlC')).VirtualKeyCode) {
            $shift_pressed = 0x10 -band [int]$PressKey.ControlKeyState
            if ($PressKey.ControlKeyState -like "*CtrlPressed*") {
                switch ($PressKey.VirtualKeyCode) {
                    67 {
                        # Ctrl + c
                        $this.reset($true)
                        break loop
                    }
                    { $_ -eq 85 -or $_ -eq 80 } {
                        # 85: Ctrl + u
                        # 80: Ctrl + p
                        $this.move_selection(-1)
                        break
                    }

                    { $_ -eq 68 -or $_ -eq 78 } {
                        # 68: Ctrl + d
                        # 78: Ctrl + n
                        $this.move_selection(1)
                        break
                    }
                }
            }
            switch ($PressKey.VirtualKeyCode) {
                { $_ -in @(9, 32) } {
                    # Tab or Space
                    if ($PSCompletions.is_single) {
                        $this.reset($true)
                        $this.filter_list[$this.selected_index].value
                        break loop
                    }
                    if ($shift_pressed) {
                        # Up
                        $this.move_selection(-1)
                    }
                    else {
                        # Down
                        $this.move_selection(1)
                    }
                    break
                }
                27 {
                    # ESC
                    $this.reset($true)
                    ''
                    break loop
                }
                13 {
                    # Enter
                    $this.filter_list[$this.selected_index].value
                    $this.reset($true)
                    break loop
                }

                ### 向上(Up/Left)
                { $_ -in @(37, 38) } {
                    $this.move_selection(-1)
                    break
                }
                ### 向下(Down/Right)
                { $_ -in @(39, 40) } {
                    $this.move_selection(1)
                    break
                }
                ### Character/Backspace
                { $PressKey.Character } {
                    # update filter
                    $old_filter = $this.filter
                    $old_filter_list = $this.filter_list
                    if ($PressKey.Character -eq 8) {
                        # backspace
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
                        $this.reset()
                        $this.filter_completions($this.origin_filter_list)
                        $this.handle_list()
                        $this.parse_list()
                        $this.new_buffer($this.offset)
                        if ($this.is_show_tip) { $this.new_tip_buffer($this.selected_index) }
                        $this.new_filter_buffer()
                        $this.new_status_buffer()
                        $this.set_selection(0)
                    }
                    else {
                        # add char
                        $this.filter += $PressKey.Character
                        $this.filter_completions($this.filter_list)
                        if (!$this.filter_list) {
                            $this.filter = $old_filter
                            $this.filter_list = $old_filter_list
                        }
                        else {
                            $this.reset()
                            $this.parse_list()
                            $this.new_buffer($this.offset)
                            if ($this.is_show_tip) { $this.new_tip_buffer($this.selected_index) }
                            $this.new_filter_buffer()
                            $this.new_status_buffer()
                            $this.set_selection(0)
                        }
                    }
                    break
                }
            }
            if ($this.is_show_tip) { $this.new_tip_buffer($this.selected_index) }
            $this.new_filter_buffer($this.filter)
            $this.new_status_buffer()
        }
    }
    catch {
        $this.reset($true)
    }
}
Add-Member -InputObject $PSCompletions.menu -MemberType ScriptMethod show_powershell_menu {
    param($filter_list)
    if ($Host.UI.RawUI.BufferSize.Height -lt 5) {
        [Microsoft.PowerShell.PSConsoleReadLine]::UndoAll()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($PSCompletions.info.min_area)
        ''
        return
    }

    $json = $PSCompletions.data.$($PSCompletions.current_cmd)
    $info = $json.info

    $max_width = 0
    $tip_max_height = 0
    $filter_list = $filter_list | ForEach-Object {
        $symbol = ($PSCompletions.replace_content($_.symbol, ' ') -split ' ' | ForEach-Object { $PSCompletions.config."symbol_$($_)" }) -join ''
        $pad = if ($symbol) { "$($PSCompletions.config.menu_between_item_and_symbol)$($symbol)" }else { '' }
        $name_with_symbol = "$($_.name[-1])$($pad)"

        $width = $this.get_length($name_with_symbol)
        if ($width -gt $max_width) { $max_width = $width }

        if ($_.tip) {
            $tip = $PSCompletions.replace_content($_.tip)
            $tip_arr = $tip -split "`n"
        }
        else {
            $tip_arr = @()
        }
        if ($tip_arr.Count -gt $tip_max_height) { $tip_max_height = $tip_arr.Count }
        @{
            name  = $name_with_symbol
            value = $_.name[-1]
            width = $width
            tip   = $tip
        }
    }
    $item_witdh = $max_width + 2
    $ui_max_width = 100
    $ui_width = if ($Host.UI.RawUI.BufferSize.Width -gt $ui_max_width) { $ui_max_width }else { $Host.UI.RawUI.BufferSize.Width }
    $max_count = ($Host.UI.RawUI.BufferSize.Height - $tip_max_height) * ([math]::Floor($ui_width) / ($item_witdh))

    $display_count = 0
    if ($max_count -lt 5 -or !$PSCompletions.config.menu_show_tip) {
        $max_count = ($Host.UI.RawUI.BufferSize.Height) * ([math]::Floor($ui_width) / ($item_witdh))
        $filter_list | ForEach-Object {
            if ($max_count -gt $display_count -and $_.name) {
                $display_count++
                [CompletionResult]::new($_.value, $_.name, 'ParameterValue', ' ')
            }
        }
    }
    else {
        $filter_list | ForEach-Object {
            if ($max_count -gt $display_count -and $_.name) {
                $display_count++
                [CompletionResult]::new($_.value, $_.name, 'ParameterValue', $_.tip)
            }
        }
    }

    if ($filter_list -is [array] -and $display_count -lt $filter_list.Count) {
        [CompletionResult]::new(' ', '...', 'ParameterValue', $PSCompletions.info.comp_hide)
        $display_count++
    }
    if ($display_count -eq 1 -and !$PSCompletions.config.enter_when_single) { ' ' }
}
