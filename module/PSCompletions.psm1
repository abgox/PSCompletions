function PSCompletions {
    $arg = $args
    function _replace($data) {
        $__d__ = $data -join ''
        $__p__ = '\{\{(.*?(\})*)(?=\}\})\}\}'
        $matches = [regex]::Matches($__d__, $__p__)
        foreach ($match in $matches) {
            $__d__ = $__d__.Replace($match.Value, (Invoke-Expression $match.Groups[1].Value))
        }
        if ($__d__ -match $__p__) { $PSCompletions.fn_replace($__d__) }else { return $__d__ }
    }
    function param_error($flag, $cmd) {
        $res = if ($flag -eq 'min') { $PSCompletions.json.param_min }
        elseif ($flag -eq 'max') { $PSCompletions.json.param_max }
        else { $PSCompletions.json.param_err }
        $PSCompletions.fn_write((_replace ($res + "`n" + $PSCompletions.json.example.$cmd)))
    }
    function _list {
        if ($arg.Length -gt 2) {
            param_error 'max' 'list'
            return
        }
        if ($arg.Length -eq 2 -and $arg[1] -ne '--remote') {
            param_error 'err' 'list'
            return
        }
        $data = [System.Collections.Generic.List[System.Object]]@()
        if ($arg[1] -eq '--remote') {
            if (!($PSCompletions.fn_download_list())) { throw (_replace $PSCompletions.json.net_error) }
            $max_len = ($PSCompletions.list  | Measure-Object -Maximum Length).Maximum
            $PSCompletions.list | ForEach-Object {
                $status = if ($PSCompletions.comp_cmd.$_) { $PSCompletions.json.list_add_done }else { $PSCompletions.json.list_add }
                $data.Add(@{
                        content = "{0,-$($max_len + 3)} {1}" -f ($_, $status)
                        color   = 'Green'
                    })
            }
            $PSCompletions.fn_less_table($data, ('Completion', 'Status', $max_len), {
                    $PSCompletions.fn_write((_replace $PSCompletions.json.list_add_tip))
                })
        }
        else {
            $max_len = ($PSCompletions.comp_cmd.keys | Measure-Object -Maximum Length).Maximum
            $PSCompletions.comp_cmd.keys | ForEach-Object {
                $alias = if ($PSCompletions.comp_cmd.$_ -eq $_) { '' }else { $PSCompletions.comp_cmd.$_ }
                $data.Add(@{
                        content = "{0,-$($max_len + 3)} {1}" -f ($_, $alias)
                        color   = 'Green'
                    })
            }
            $PSCompletions.fn_less_table($data, ('Completion', 'Alias', $max_len))
        }
    }
    function _add {
        if ($arg.Length -lt 2) {
            param_error 'min' 'add'
            return
        }
        if (!($PSCompletions.fn_download_list())) { return }
        $arg[1..($arg.Length - 1)] | ForEach-Object {
            if ($_ -in $PSCompletions.list) {
                $PSCompletions.fn_add_completion($_)
            }
            else {
                $PSCompletions.fn_write((_replace $PSCompletions.json.add_error))
            }
        }
    }
    function _remove {
        if ($arg.Length -lt 2) {
            param_error 'min' 'rm'
            return
        }
        $arg[1..($arg.Length - 1)] | ForEach-Object {
            if ($_ -in $PSCompletions.comp_cmd.keys) {
                $dir = $PSCompletions.fn_join_path($PSScriptRoot, 'completions', $_)
                Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
                if (!(Test-Path $dir)) {
                    $PSCompletions.fn_write((_replace $PSCompletions.json.remove_done))
                }
            }
            else { $PSCompletions.fn_write((_replace $PSCompletions.json.remove_err)) }
        }
    }
    function _update {
        $comp_cmd = $PSCompletions.comp_cmd.keys | Where-Object { $_ -in $PSCompletions.list }
        function _do {
            $update_list = [System.Collections.Generic.List[string]]@()
            try {
                $comp_cmd | ForEach-Object {
                    $url = $PSCompletions.url + '/completions/' + $_ + '/guid.txt'
                    $response = Invoke-WebRequest -Uri  $url
                    if ($response.StatusCode -eq 200) {
                        $content = $response.Content.Trim()
                        $guid = $PSCompletions.fn_get_raw_content($PSCompletions.fn_join_path($PSCompletions.path.completions, $_, 'guid.txt'))
                        if ($guid -ne $content) { $update_list.Add($_) }
                    }
                }
            }
            catch {
                $PSCompletions.fn_write((_replace $PSCompletions.json.net_error))
                return
            }
            $update_list | Out-File $PSCompletions.path.update -Force -Encoding utf8
            $PSCompletions.update = $update_list
            if ($update_list) {
                $PSCompletions.fn_write((_replace $PSCompletions.json.update_has))
            }
            else {
                $PSCompletions.fn_write((_replace $PSCompletions.json.update_no))
            }
        }
        if ($arg.Length -eq 1) { _do }
        else {
            if ($arg[1] -eq '*') {
                foreach ($_ in $PSCompletions.update) {
                    $PSCompletions.fn_add_completion($_, $true, $true)
                }
            }
            else {
                $arg[1..($arg.Length - 1)] | ForEach-Object {
                    if ($_ -in $comp_cmd) {
                        $PSCompletions.fn_add_completion($_, $true, $true)
                    }
                    else {
                        $PSCompletions.fn_write((_replace $PSCompletions.json.update_error))
                    }
                }
            }
            _do
        }
    }
    function _search {
        if ($arg.Length -lt 2) {
            param_error 'min' 'search'
            return
        }
        elseif ($arg.Length -gt 2) {
            param_error 'max' 'search'
            return
        }
        if (!(($PSCompletions.fn_download_list()))) { return }
        $res = $PSCompletions.list | Where-Object { $_ -like $arg[1] }
        if ($res) {
            $PSCompletions.fn_less($res, 'Cyan')
        }
        else {
            $PSCompletions.fn_write((_replace $PSCompletions.json.search_err))
        }
    }
    function _which {
        if ($arg.Length -lt 2) {
            param_error 'min' 'which'
            return
        }
        $arg[1..($arg.Length - 1)] | ForEach-Object {
            if ($_ -in $PSCompletions.comp_cmd.keys) {
                Write-Output (Join-Path $PSCompletions.path.completions $_)
            }
            else {
                $PSCompletions.fn_write((_replace $PSCompletions.json.which_err))
            }
        }
    }
    function _alias {
        $cmd_list = @('add', 'rm', 'list', 'reset')
        if ($arg.Length -eq 1) {
            param_error 'min' 'alias'
            return
        }
        if ($arg[1] -notin $cmd_list) {
            $PSCompletions.fn_write((_replace $PSCompletions.json.param_errs))
            return
        }
        if ($arg[1] -eq 'add') {
            if ($arg.Length -lt 4) {
                param_error 'min' 'alias_add'
                return
            }
            elseif ($arg.Length -gt 4) {
                param_error 'max' 'alias_add'
                return
            }
        }
        if ($arg[1] -eq 'rm') {
            if ($arg.Length -lt 3) {
                param_error 'min' 'alias_rm'
                return
            }
        }
        if ($arg.Length -gt 2) {
            if ($arg[1] -eq 'list') {
                param_error 'max' 'alias_list'
                return
            }
            elseif ($arg[1] -eq 'reset') {
                param_error 'max' 'alias_reset'
                return
            }
        }
        if ($arg[1] -eq 'list') {
            $data = [System.Collections.Generic.List[System.Object]]@()
            $max_len = ($PSCompletions.comp_cmd.keys | Measure-Object -Maximum Length).Maximum
            $PSCompletions.comp_cmd.keys | Where-Object { $_ -ne $PSCompletions.comp_cmd.$_ } | ForEach-Object {
                $data.Add(@{
                        content = "{0,-$($max_len + 3)} {1}" -f ($_, $PSCompletions.comp_cmd.$_)
                        color   = 'Green'
                    })
            }
            $PSCompletions.fn_less_table($data, ('Completion', 'Alias', $max_len))
        }
        elseif ($arg[1] -eq 'add') {
            if ($arg[2] -in $PSCompletions.comp_cmd.Keys) {
                $cmd = (Get-Command).Name | Where-Object { $_ -eq $arg[-1] }
                $alias = (Get-Alias).Name | Where-Object { $_ -eq $arg[-1] }
                if ($cmd -or $alias) {
                    $PSCompletions.fn_write((_replace ($PSCompletions.json.param_err + "`n" + $PSCompletions.json.alias_add_err)))
                    return
                }
                $arg[3] | Out-File $PSCompletions.fn_join_path($PSCompletions.path.completions, $arg[2], 'alias.txt') -Force -Encoding utf8
                $PSCompletions.fn_write((_replace $PSCompletions.json.alias_add_done))
            }
            else {
                $PSCompletions.fn_write((_replace $PSCompletions.json.alias_err))
            }
        }
        elseif ($arg[1] -eq 'rm') {
            $rm_list = $arg[2..($arg.Length - 1)]
            $del_list = [System.Collections.Generic.List[string]]@()
            $error_list = [System.Collections.Generic.List[string]]@()
            $alias_list = @{}
            $PSCompletions.comp_cmd.Keys | ForEach-Object {
                $alias = $PSCompletions.comp_cmd.$_
                if ($_ -ne $alias) { $alias_list.$alias = $_ }
            }
            foreach ($item in $rm_list) {
                if ($item -in $alias_list.Keys) {
                    $del_list.Add($item)
                    Remove-Item $PSCompletions.fn_join_path($PSCompletions.path.completions, $alias_list.$item, 'alias.txt') -Force -ErrorAction SilentlyContinue
                }
                else { $error_list.Add($item) }
            }
            if ($error_list) {
                $PSCompletions.fn_write((_replace ($PSCompletions.json.alias_rm_err)))
            }
            if ($del_list) {
                $PSCompletions.fn_write((_replace $PSCompletions.json.alias_rm_done))
            }
        }
        else {
            $null = $PSCompletions.fn_confirm($PSCompletions.json.alias_reset_confirm, {
                    $del_list = [System.Collections.Generic.List[string]]@()
                    $reset_list = $PSCompletions.comp_cmd.keys | Where-Object { $PSCompletions.comp_cmd.$_ -ne $_ }
                    $alias_list = @{}
                    foreach ($_ in $reset_list) {
                        $alias = $PSCompletions.comp_cmd.$_
                        $del_list.Add($alias)
                        $alias_list.$alias = $_
                        Remove-Item $PSCompletions.fn_join_path($PSCompletions.path.completions, $_, 'alias.txt') -Force -ErrorAction SilentlyContinue
                    }
                    $PSCompletions.fn_set_config('root_cmd', 'psc')
                    if ($del_list) {
                        $PSCompletions.fn_write((_replace $PSCompletions.json.alias_reset_done))
                    }
                })
        }
    }
    function _order {
        if ($arg.Length -le 2) {
            if ($arg[1] -ne 'reset') {
                param_error 'err' 'order'
            }
            else {
                param_error 'min' 'order'
            }
            return
        }
        $del_list = [System.Collections.Generic.List[string]]@()
        $err_list = [System.Collections.Generic.List[string]]@()
        if ($arg[2] -eq '*') {
            $PSCompletions.comp_cmd.keys | ForEach-Object {
                $dir = PSCompletions which $_
                Remove-Item (Join-Path $dir 'order.json') -Force -ErrorAction SilentlyContinue
                $del_list.Add($_)
            }
        }
        else {
            $arg[2..($arg.Length - 1)] | ForEach-Object {
                if ($_ -in $PSCompletions.comp_cmd.keys) {
                    $dir = PSCompletions which $_
                    Remove-Item (Join-Path $dir 'order.json') -Force -ErrorAction SilentlyContinue
                    $del_list.Add($_)
                }
                else {
                    $err_list.Add($_)
                }
            }
        }
        if ($del_list) {
            $PSCompletions.fn_write((_replace $PSCompletions.json.order_done))
        }
        if ($err_list) {
            $PSCompletions.fn_write((_replace $PSCompletions.json.order_err))
        }
    }
    function _config {
        if ($arg.Length -lt 2) {
            param_error 'min' 'config'
            return
        }
        elseif ($arg.Length -gt 4) {
            param_error 'max' 'config'
            return
        }
        if ($arg.Length -eq 2) {
            if ($arg[1] -in $PSCompletions.config.Keys) {
                Write-Output ($PSCompletions.config[$arg[1]])
            }
            else {
                if ($arg[1] -eq 'reset') {
                    if ($PSVersionTable.Platform -ne 'Unix') {
                        $PSCompletions.lang = (Get-WinSystemLocale).name
                    }
                    else {
                        if ($env:LANG -like 'zh[-_]CN*') {
                            $PSCompletions.lang = 'zh-CN'
                        }
                        else {
                            $PSCompletions.lang = 'en-US'
                        }
                    }
                    $c = [ordered]@{
                        root_cmd       = 'psc'
                        github         = 'https://github.com/abgox/PSCompletions'
                        gitee          = 'https://gitee.com/abgox/PSCompletions'
                        language       = $PSCompletions.lang
                        update         = 1
                        LRU            = 5
                        run_with_admin = 1
                        module_update  = 1
                        sym            = [char]::ConvertFromUtf32(128516)
                        sym_wr         = [char]::ConvertFromUtf32(128526)
                        sym_opt        = [char]::ConvertFromUtf32(129300)
                    }
                    $flag = $PSCompletions.fn_confirm($PSCompletions.json.config_reset, {
                            $c | ConvertTo-Json | Out-File $PSCompletions.path.env
                        })
                    if ($flag) {
                        $PSCompletions.config = $c
                        $PSCompletions.fn_write((_replace $PSCompletions.json.config_reset_done))
                    }
                    return
                }
                if ($arg[1] -eq 'symbol') {
                    param_error 'min' 'config'
                }
                else {
                    $PSCompletions.fn_write((_replace $PSCompletions.json.config_err))
                }
            }
        }
        else {
            if ($arg[1] -in $PSCompletions.config.Keys) {
                if ($arg.Length -gt 3) {
                    param_error 'max' 'config'
                    return
                }
                if ($arg[1] -eq 'root_cmd') {
                    $cmd = (Get-Command).Name | Where-Object { $_ -eq $arg[2] }
                    $alias = (Get-Alias).Name | Where-Object { $_ -eq $arg[2] }
                    if ($cmd -or $alias) {
                        $PSCompletions.fn_write((_replace ($PSCompletions.json.param_err + "`n" + $PSCompletions.json.alias_add_err)))
                        return
                    }
                    $arg[2] | Out-File $PSCompletions.fn_join_path($PSCompletions.path.completions, 'PSCompletions', 'alias.txt') -Force -Encoding utf8
                }
                elseif ($arg[1] -eq 'language') {
                    $PSCompletions.comp_data = [ordered]@{}
                }
                $old_value = $PSCompletions.config.$($arg[1])
                $PSCompletions.fn_set_config($arg[1], $arg[2])
                $PSCompletions.fn_write((_replace $PSCompletions.json.config_done))
            }
            elseif ($arg[1] -eq 'symbol') {
                switch ($arg[2]) {
                    'SpaceTab' {
                        if ($arg[3]) {
                            $old_value = $PSCompletions.config.sym
                            $PSCompletions.fn_set_config('sym', $arg[3])
                            $PSCompletions.fn_write((_replace $PSCompletions.json.config_symbol_done))
                        }
                        else {
                            $PSCompletions.config.sym
                        }
                    }
                    'WriteSpaceTab' {
                        if ($arg[3]) {
                            $old_value = $PSCompletions.config.sym_wr
                            $PSCompletions.fn_set_config('sym_wr', $arg[3])
                            $PSCompletions.fn_write((_replace $PSCompletions.json.config_symbol_done))
                        }
                        else {
                            $PSCompletions.config.sym_wr
                        }
                    }
                    'OptionsTab' {
                        if ($arg[3]) {
                            $old_value = $PSCompletions.config.sym_opt
                            $PSCompletions.fn_set_config('sym_opt', $arg[3])
                            $PSCompletions.fn_write((_replace $PSCompletions.json.config_symbol_done))
                        }
                        else {
                            $PSCompletions.config.sym_opt
                        }
                    }
                    'reset' {
                        if ($arg[3]) {
                            param_error 'max' 'config_symbol_reset'
                        }
                        else {
                            $symbol = @{
                                sym     = @('SpaceTab', [char]::ConvertFromUtf32(128516))
                                sym_wr  = @('WriteSpaceTab', [char]::ConvertFromUtf32(128526))
                                sym_opt = @('OptionsTab', [char]::ConvertFromUtf32(129300))
                            }
                            $symbol_list = @()
                            foreach ($item in $symbol.Keys) {
                                $symbol_list += @{
                                    type      = $symbol.$item[0]
                                    old_value = $PSCompletions.config.$item
                                    value     = $symbol.$item[1]
                                }
                                $PSCompletions.fn_set_config($item, $symbol.$item[1])
                            }
                            $PSCompletions.fn_write((_replace $PSCompletions.json.config_symbol_reset_done))
                        }
                    }
                    Default {
                        $PSCompletions.fn_write((_replace $PSCompletions.json.config_symbol_err))
                    }
                }
            }
            else {
                $PSCompletions.fn_write((_replace $PSCompletions.json.config_err))
            }
        }
    }
    function _completion {
        if ($arg.Length -lt 4) {
            param_error 'min' 'completion'
            return
        }
        if ($arg.Length -gt 4) {
            param_error 'max' 'completion'
            return
        }
        if ($arg[1] -notin $PSCompletions.comp_cmd.keys) {
            $PSCompletions.fn_write((_replace $PSCompletions.json.comp_err))
            return
        }
        if ($arg[2] -ne 'language' -and !$PSCompletions.comp_config.$($arg[1]).$($arg[2])) {
            $PSCompletions.fn_write((_replace $PSCompletions.json.comp_conf_err))
            return
        }

        $comp_config = $PSCompletions.comp_config
        if (!$comp_config.($arg[1])) {
            $comp_config.($arg[1]) = @{}
        }
        $old_value = $comp_config.($arg[1]).($arg[2])
        $comp_config.($arg[1]).($arg[2]) = $arg[3]

        $PSCompletions.comp_config = $comp_config
        $PSCompletions.fn_write((_replace $PSCompletions.json.comp_done))
    }
    function _ui {
        if (!$PSCompletions.ui) {
            $PSCompletions.fn_write((_replace $PSCompletions.json.ui_err))
            return
        }
        if ($arg[1] -notin @('theme', 'style' , 'custom', 'menu', 'reset')) {
            param_error 'err' 'ui'
            return
        }
        switch ($arg[1]) {
            'theme' {
                $theme_list = @('default', 'magenta')
                if (!$arg[2]) {
                    param_error 'min' 'ui_theme'
                    return
                }
                if ($arg[3]) {
                    param_error 'max' 'ui_theme'
                    return
                }
                if ($arg[2] -notin $theme_list) {
                    param_error 'err' 'ui_theme'
                    return
                }
                switch ($arg[2]) {
                    'magenta' {
                        $PSCompletions.ui.color = @{
                            item_text     = 'DarkGray'
                            item_back     = 'White'
                            selected_text = 'white'
                            selected_back = 'DarkMagenta'
                            filter_text   = 'DarkMagenta'
                            filter_back   = 'White'
                            border_text   = 'DarkMagenta'
                            border_back   = 'White'
                            status_text   = 'DarkMagenta'
                            status_back   = 'White'
                            tip_text      = 'DarkGray'
                            tip_back      = 'White'
                        }
                    }
                    # default
                    Default {
                        $PSCompletions.ui.color = @{
                            item_text     = 'Gray'
                            item_back     = 'Black'
                            selected_text = 'white'
                            selected_back = 'DarkGray'
                            filter_text   = 'Yellow'
                            filter_back   = 'Black'
                            border_text   = 'DarkGray'
                            border_back   = 'Black'
                            status_text   = 'Blue'
                            status_back   = 'Black'
                            tip_text      = 'Cyan'
                            tip_back      = 'Black'
                        }
                    }
                }
                $PSCompletions.fn_write((_replace $PSCompletions.json.ui_theme_done))
            }
            'style' {
                switch ($arg[2]) {
                    'double_line_rect_border' {
                        $PSCompletions.ui.config.line = @{
                            horizontal   = [string][char]9552
                            vertical     = [string][char]9553
                            top_left     = [string][char]9556
                            bottom_left  = [string][char]9562
                            top_right    = [string][char]9559
                            bottom_right = [string][char]9565
                        }
                        $PSCompletions.fn_write((_replace $PSCompletions.json.ui_style_done))
                    }
                    'single_line_rect_border' {
                        $PSCompletions.ui.config.line = @{
                            horizontal   = [string][char]9472
                            vertical     = [string][char]9474
                            top_left     = [string][char]9484
                            bottom_left  = [string][char]9492
                            top_right    = [string][char]9488
                            bottom_right = [string][char]9496
                        }
                        $PSCompletions.fn_write((_replace $PSCompletions.json.ui_style_done))
                    }
                    'single_line_round_border' {
                        $PSCompletions.ui.config.line = @{
                            horizontal   = [string][char]9472
                            vertical     = [string][char]9474
                            top_left     = [string][char]9581
                            bottom_left  = [string][char]9584
                            top_right    = [string][char]9582
                            bottom_right = [string][char]9583
                        }
                        $PSCompletions.fn_write((_replace $PSCompletions.json.ui_style_done))
                    }
                    Default {
                        $PSCompletions.fn_write((_replace $PSCompletions.json.ui_style_err))
                    }
                }

            }
            'custom' {
                if (!$arg[2]) {
                    param_error 'min' 'ui_custom'
                    return
                }
                if ($arg[5]) {
                    param_error 'max' 'ui_custom'
                    return
                }
                if ($arg[2] -notin @('color', 'line', 'config')) {
                    param_error 'err' 'ui_custom'
                    return
                }
                if ($arg[2] -eq 'color') {
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
                    if ($arg[4] -notin $available_color) {
                        $PSCompletions.fn_write((_replace $PSCompletions.json.color_err))
                        return
                    }
                    $old_value = $PSCompletions.ui.color.($arg[3])
                    $PSCompletions.ui.color.($arg[3]) = $arg[4]
                    $PSCompletions.fn_write((_replace $PSCompletions.json.color_done))
                }
                elseif ($arg[2] -eq 'line') {
                    # line
                    $old_value = $PSCompletions.ui.config.line.($arg[3])
                    $PSCompletions.ui.config.line.($arg[3]) = $arg[4]
                    $PSCompletions.fn_write((_replace $PSCompletions.json.line_done))
                }
                else {
                    # config
                    if ($arg[3] -eq 'filter_symbol') {
                        if ($arg[4].Length -ne 2) {
                            $PSCompletions.fn_write((_replace $PSCompletions.json.filter_symbol_err))
                            return
                        }
                    }
                    $old_value = $PSCompletions.ui.config.($arg[3])
                    $PSCompletions.ui.config.($arg[3]) = $arg[4]
                    $PSCompletions.fn_write((_replace $PSCompletions.json.ui_config_done))
                }
            }
            'menu' {
                if (!$arg[2]) {
                    param_error 'min' 'ui_menu'
                    return
                }
                if ($arg[3]) {
                    param_error 'max' 'ui_menu'
                    return
                }
                if ($arg[2] -notin @('default', 'powershell')) {
                    param_error 'err' 'ui_menu'
                    return
                }
                if ($arg[2] -eq 'default') {
                    $PSCompletions.ui.config.enable_ui = 1
                }
                else {
                    $PSCompletions.ui.config.enable_ui = 0
                }
                $PSCompletions.fn_write((_replace $PSCompletions.json.ui_menu_done))
            }
            # reset
            Default {
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
                $PSCompletions.fn_write((_replace $PSCompletions.json.ui_reset_done))
            }
        }
    }
    function _help {
        $PSCompletions.fn_write((_replace $PSCompletions.json.description))
    }
    $need_init = $true
    switch ($arg[0]) {
        'list' {
            _list
            $need_init = $null
        }
        'add' {
            _add
        }
        'rm' {
            _remove
        }
        'update' {
            _update
        }
        'search' {
            _search
            $need_init = $null
        }
        'which' {
            _which
            $need_init = $null
        }
        'alias' {
            _alias
        }
        'order' {
            _order
        }
        'config' {
            _config
        }
        'completion' {
            _completion
            $PSCompletions.has_config_update = $true
        }
        'ui' {
            _ui
            $PSCompletions.has_config_update = $true
        }
        default {
            if ($arg.Length -eq 1) {
                $PSCompletions.fn_write((_replace $PSCompletions.json.cmd_error))
            }
            else { _help }
            $need_init = $null
        }
    }
    if ($need_init) { $PSCompletions.fn_init() }
    if ($PSCompletions.has_config_update -and $PSCompletions.ui) {
        if (!$PSCompletions.ui.color) {
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
        }
        if (!$PSCompletions.ui.config) {
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
        }
        @{
            ui          = $PSCompletions.ui.config
            color       = $PSCompletions.ui.color
            comp_config = $PSCompletions.comp_config
        } | ConvertTo-Json | Out-File $PSCompletions.path.config -Encoding utf8
    }
}
