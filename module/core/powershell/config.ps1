
$PSCompletions.default.env = @{
    # env
    language      = $PSUICulture
    update        = 1
    module_update = 1
    github        = 'https://github.com/abgox/PSCompletions'
    gitee         = 'https://gitee.com/abgox/PSCompletions'
    url           = ''
}
$PSCompletions.default.symbol = @{
    symbol_SpaceTab      = [char]::ConvertFromUtf32([convert]::ToInt32(("U+1F604" -replace 'U\+', '0x'), 16))
    symbol_WriteSpaceTab = [char]::ConvertFromUtf32([convert]::ToInt32(("U+1F60E" -replace 'U\+', '0x'), 16))
    symbol_OptionTab     = [char]::ConvertFromUtf32([convert]::ToInt32(("U+1F914" -replace 'U\+', '0x'), 16))
}
$PSCompletions.default.menu_line = @{
    # menu line
    menu_line_horizontal   = [string][char]9552
    menu_line_vertical     = [string][char]9553
    menu_line_top_left     = [string][char]9556
    menu_line_bottom_left  = [string][char]9562
    menu_line_top_right    = [string][char]9559
    menu_line_bottom_right = [string][char]9565
}
$PSCompletions.default.menu_color = @{
    # menu color
    menu_color_item_text     = 'Blue'
    menu_color_item_back     = 'Black'
    menu_color_selected_text = 'white'
    menu_color_selected_back = 'DarkGray'
    menu_color_filter_text   = 'DarkYellow'
    menu_color_filter_back   = 'Black'
    menu_color_border_text   = 'DarkGray'
    menu_color_border_back   = 'Black'
    menu_color_status_text   = 'DarkBlue'
    menu_color_status_back   = 'Black'
    menu_color_tip_text      = 'DarkCyan'
    menu_color_tip_back      = 'Black'
}
$PSCompletions.default.menu_config = @{
    # menu config
    disable_cache                = 0
    enter_when_single            = 0
    menu_enable                  = 1
    menu_show_tip                = 1
    menu_completions_sort        = 1
    menu_selection_with_margin   = 1
    menu_tip_follow_cursor       = 0
    menu_tip_cover_buffer        = 0
    menu_list_follow_cursor      = 1
    menu_list_cover_buffer       = 0
    menu_list_margin_left        = 0
    menu_list_margin_right       = 0
    menu_list_min_width          = 10
    menu_is_prefix_match         = 0
    menu_above_margin_bottom     = 0
    menu_above_list_max_count    = -1
    menu_below_list_max_count    = -1
    menu_between_item_and_symbol = ' '
    menu_status_symbol           = '/'
    menu_filter_symbol           = '[]'
}
# completion config
$PSCompletions.default.comp_config = @{}

Add-Member -InputObject $PSCompletions -MemberType ScriptMethod get_config {
    function ConvertFrom-JsonToHashtable([string]$json) {
        # Handle json string
        $matches = [regex]::Matches($json, '\s*"\s*"\s*:')
        foreach ($match in $matches) {
            $json = $json -replace $match.Value, "`"empty_key_$([System.Guid]::NewGuid().Guid)`":"
        }
        $json = [regex]::Replace($json, ",`n?(\s*`n)?\}", "}")
        function ConvertToHashtable($obj) {
            $hash = @{}
            if ($obj -is [System.Management.Automation.PSCustomObject]) {
                $obj | Get-Member -MemberType Properties | ForEach-Object {
                    $k = $_.Name # Key
                    $v = $obj.$k # Value
                    if ($v -is [System.Collections.IEnumerable] -and $v -isnot [string]) {
                        # Handle array
                        $arr = @()
                        foreach ($item in $v) {
                            $arr += if ($item -is [System.Management.Automation.PSCustomObject]) { ConvertToHashtable($item) }else { $item }
                        }
                        $hash[$k] = $arr
                    }
                    elseif ($v -is [System.Management.Automation.PSCustomObject]) {
                        # Handle object
                        $hash[$k] = ConvertToHashtable($v)
                    }
                    else { $hash[$k] = $v }
                }
            }
            else { $hash = $obj }
            $hash
        }
        # Recurse
        ConvertToHashtable ($json | ConvertFrom-Json)
    }
    if (Test-Path $this.path.config) {
        $c = ConvertFrom-JsonToHashtable $this.get_raw_content($this.path.config)
        if ($c) {
            @('env', 'symbol', 'menu_line', 'menu_color', 'menu_config') | ForEach-Object {
                foreach ($config in $this.default.$_.Keys) {
                    if ($config -notin $c.keys) {
                        $hasDiff = $true
                        $c.$config = $this.default.$_.$config
                    }
                }
            }
            if (!$c.comp_config) {
                $hasDiff = $true
                $c.comp_config = @{}
            }
            if ($hasDiff) {
                $c | ConvertTo-Json | Out-File $this.path.config -Encoding utf8 -Force
            }
            return $c
        }
        else {
            $need_init = $true
        }
    }
    else {
        $need_init = $true
    }
    if ($need_init) {
        $c = @{}
        @('env', 'symbol', 'menu_line', 'menu_color', 'menu_config') | ForEach-Object {
            foreach ($config in $this.default.$_.Keys) {
                $c.$config = $this.default.$_.$config
            }
        }
        $c.comp_config = @{}
        $c | ConvertTo-Json | Out-File $this.path.config -Encoding utf8 -Force
    }
    return $c
}

Add-Member -InputObject $PSCompletions -MemberType ScriptMethod set_config {
    param ([string]$k, $v)
    $c = $this.get_config()
    $c.$k = $v
    $this.config = $c
    $c | ConvertTo-Json | Out-File $this.path.config -Encoding utf8 -Force
}
