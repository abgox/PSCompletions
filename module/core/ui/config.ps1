if (Test-Path $PSCompletions.path.config) {
    $PSCompletions.total_config = $PSCompletions.fn_get_raw_content($PSCompletions.path.config) | ConvertFrom-Json

    if ($PSCompletions.total_config.comp_config) {
        $PSCompletions.total_config.comp_config.PSObject.Properties.Name | ForEach-Object {
            $PSCompletions.comp_config.$_ = @{}
            foreach ($item in $PSCompletions.total_config.comp_config.$_.PSObject.Properties.Name) {
                $PSCompletions.comp_config.$_.$item = $PSCompletions.total_config.comp_config.$_.$item
            }
        }
    }

    $PSCompletions.ui.color = @{
        item_text     = 'Gray'
        item_back     = 'Black'
        selected_text = 'white'
        selected_back = 'DarkGray'
        filter_text   = 'DarkYellow'
        filter_back   = 'Black'
        border_text   = 'DarkGray'
        border_back   = 'Black'
        status_text   = 'DarkBlue'
        status_back   = 'Black'
        tip_text      = 'DarkCyan'
        tip_back      = 'Black'
    }
    if ($PSCompletions.total_config.color) {
        $available_color = @(
            'White', 'Black',
            'Gray', 'DarkGray'
            'Red', 'DarkRed',
            'Green', 'DarkGreen',
            'Blue', 'DarkBlue',
            'Cyan', 'DarkCyan',
            'Yellow', 'DarkYellow',
            'Magenta', 'DarkMagenta'
        )
        $PSCompletions.ui.color.Keys | ForEach-Object {
            if ($PSCompletions.total_config.color.$_ -and $PSCompletions.total_config.color.$_ -in $available_color) {
                $PSCompletions.ui.color.$_ = $PSCompletions.total_config.color.$_
            }
            else {
                $PSCompletions.temp.is_write = $true
            }
        }
    }
    else {
        $PSCompletions.temp.is_write = $true
    }

    $PSCompletions.ui.config = @{}
    $PSCompletions.temp.ui_config = @{
        enable_ui              = 1
        follow_cursor          = 0
        above_list_max         = 10
        list_margin_right      = 1
        tip_margin_right       = 0
        fast_scroll_item_count = 10
        count_symbol           = '/'
        filter_symbol          = '[]'
        line                   = @{
            horizontal   = [string][char]9552
            vertical     = [string][char]9553
            top_left     = [string][char]9556
            bottom_left  = [string][char]9562
            top_right    = [string][char]9559
            bottom_right = [string][char]9565
        }
    }
    if ($PSCompletions.total_config.ui) {
        $PSCompletions.total_config.ui.PSObject.Properties.Name | ForEach-Object {
            $PSCompletions.ui.config.$_ = $PSCompletions.total_config.ui.$_
        }
        $PSCompletions.temp.ui_config.Keys | ForEach-Object {
            if ($_ -notin $PSCompletions.ui.config.Keys) {
                $PSCompletions.temp.is_write = $true
                $PSCompletions.ui.config.$_ = $PSCompletions.temp.ui_config.$_
            }
        }
    }
    else {
        $PSCompletions.ui.config = $PSCompletions.temp.ui_config
        $PSCompletions.temp.is_write = $true
    }

    if ($PSCompletions.temp.is_write) {
        $PSCompletions.total_config = @{
            ui    = $PSCompletions.ui.config
            color = $PSCompletions.ui.color
        }
        if ($PSCompletions.comp_config.Count) {
            $PSCompletions.total_config.comp_config = $PSCompletions.comp_config
        }
        $PSCompletions.total_config | ConvertTo-Json | Out-File $PSCompletions.path.config -Encoding utf8
    }
}
else {
    $PSCompletions.ui.color = @{
        item_text     = 'Gray'
        item_back     = 'Black'
        selected_text = 'white'
        selected_back = 'DarkGray'
        filter_text   = 'DarkYellow'
        filter_back   = 'Black'
        border_text   = 'DarkGray'
        border_back   = 'Black'
        status_text   = 'DarkBlue'
        status_back   = 'Black'
        tip_text      = 'DarkCyan'
        tip_back      = 'Black'
    }
    $PSCompletions.ui.config = @{
        enable_ui              = 1
        follow_cursor          = 0
        above_list_max         = 10
        list_margin_right      = 1
        tip_margin_right       = 0
        fast_scroll_item_count = 10
        count_symbol           = '/'
        filter_symbol          = '[]'
        line                   = @{
            horizontal   = [string][char]9552
            vertical     = [string][char]9553
            top_left     = [string][char]9556
            bottom_left  = [string][char]9562
            top_right    = [string][char]9559
            bottom_right = [string][char]9565
        }
    }
    $PSCompletions.total_config = @{
        ui    = $PSCompletions.ui.config
        color = $PSCompletions.ui.color
    }
    if ($PSCompletions.comp_config.Count) {
        $PSCompletions.total_config.comp_config = $PSCompletions.comp_config
    }
    $PSCompletions.total_config | ConvertTo-Json | Out-File $PSCompletions.path.config -Encoding utf8
}
