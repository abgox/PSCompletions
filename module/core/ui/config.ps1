if (Test-Path($PSCompletions.path.config)) {
    $PSCompletions.total_config = Get-Content -Raw $PSCompletions.path.config | ConvertFrom-Json
    $PSCompletions.ui.config = $PSCompletions.total_config.ui
    $PSCompletions.ui.color = $PSCompletions.total_config.color
    if ($PSCompletions.total_config.comp_config) {
        $PSCompletions.total_config.comp_config.PSObject.Properties.Name | ForEach-Object {
            $PSCompletions.comp_config.$_ = @{}
            foreach ($item in $PSCompletions.total_config.comp_config.$_.PSObject.Properties.Name) {
                $PSCompletions.comp_config.$_.$item = $PSCompletions.total_config.comp_config.$_.$item
            }
        }
    }
}
else {
    $PSCompletions.ui.color = @{
        item          = 'Gray'
        item_back     = 'Black'
        selected      = 'white'
        selected_back = 'DarkGray'
        filter        = 'DarkYellow'
        filter_back   = 'Black'
        border        = 'DarkGray'
        border_back   = 'Black'
        status        = 'DarkBlue'
        status_back   = 'Black'
        tip           = 'DarkCyan'
        tip_back      = 'Black'
    }
    $PSCompletions.ui.config = @{
        enable_ui              = 1
        follow_cursor          = 0
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
        ui = $PSCompletions.ui.config
        color = $PSCompletions.ui.color
    }
    if($PSCompletions.comp_config.Count){
        $PSCompletions.total_config.comp_config = $PSCompletions.comp_config
    }
    $PSCompletions.total_config | ConvertTo-Json | Out-File $PSCompletions.path.config -Encoding utf8
}
