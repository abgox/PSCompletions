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
    $filter_list = foreach ($_ in $filter_list) {
        $symbol = foreach ($c in $_.symbol) { $PSCompletions.config."symbol_$($c)" }
        $symbol = $symbol -join ''
        $pad = if ($symbol) { "$($PSCompletions.config.menu_between_item_and_symbol)$($symbol)" }else { '' }
        $name_with_symbol = "$($_.name[-1])$($pad)"

        $width = $this.get_length($name_with_symbol)
        if ($width -gt $max_width) { $max_width = $width }

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
    $item_witdh = $max_width + 2
    $ui_max_width = 100
    $ui_width = if ($Host.UI.RawUI.BufferSize.Width -gt $ui_max_width) { $ui_max_width }else { $Host.UI.RawUI.BufferSize.Width }
    $max_count = ($Host.UI.RawUI.BufferSize.Height - $tip_max_height) * ([math]::Floor($ui_width) / ($item_witdh))

    $display_count = 0
    if ($max_count -lt 5 -or !$PSCompletions.config.menu_show_tip) {
        $max_count = ($Host.UI.RawUI.BufferSize.Height) * ([math]::Floor($ui_width) / ($item_witdh))
        foreach ($_ in $filter_list) {
            if ($max_count -gt $display_count -and $_.name) {
                $display_count++
                [CompletionResult]::new($_.value, $_.name, 'ParameterValue', ' ')
            }
        }
    }
    else {
        foreach ($_ in $filter_list) {
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
