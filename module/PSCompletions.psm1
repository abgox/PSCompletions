Set-Item -Path Function:$($PSCompletions.config.function_name) -Value {
    $arg = $args

    # ? 由于此处使用 $PSCompletions.replace_content 会导致其无法使用外部变量，所以重新定义一个函数以供使用
    function _replace {
        param ($data, $separator = '')
        $data = $data -join $separator
        $pattern = '\{\{(.*?(\})*)(?=\}\})\}\}'
        $matches = [regex]::Matches($data, $pattern)
        foreach ($match in $matches) {
            $data = $data.Replace($match.Value, (Invoke-Expression $match.Groups[1].Value) -join $separator )
        }
        if ($data -match $pattern) { (_replace $data) }else { return $data }
    }
    function Show-ParamError($flag, $cmd, $err_info = $PSCompletions.info.$cmd.err.$flag, $example = $PSCompletions.info.$cmd.example) {
        $err = if ($flag -eq 'min') { $PSCompletions.info.param_min }
        elseif ($flag -eq 'max') { $PSCompletions.info.param_max }
        else { $PSCompletions.info.param_err }
        $PSCompletions.write_with_color((_replace $err))

        if ($err_info) {
            $PSCompletions.write_with_color((_replace $err_info))
        }
        if ($example) {
            $PSCompletions.write_with_color($PSCompletions.info.example_color + (_replace $example))
        }
    }
    function Show-List() {
        $max_len = ($PSCompletions.cmd.keys | Measure-Object -Maximum Length).Maximum
        $max_len = if ($max_len -lt 10) { 10 }else { $max_len }
        foreach ($_ in $PSCompletions.cmd.keys) {
            $alias = $PSCompletions.cmd.$_ -join ' '
            $data.Add(@{
                    content = "{0,-$($max_len + 3)} {1}" -f ($_, $alias)
                    color   = 'Green'
                })
        }
        $PSCompletions.show_with_less_table($data, ('Completion', 'Alias', $max_len))
    }
    function Out-Config {
        $PSCompletions.config | ConvertTo-Json -Depth 100 -Compress | Out-File $PSCompletions.path.config -Force -Encoding utf8
    }
    function _list {
        if ($arg.Length -gt 2) {
            Show-ParamError 'max' 'list'
            return
        }
        $data = [System.Collections.Generic.List[System.Object]]@()
        if ($arg.Length -eq 2) {
            if ($arg[1] -eq '--remote') {
                if (!($PSCompletions.download_list())) {
                    $PSCompletions.write_with_color((_replace $PSCompletions.info.err.download_list))
                    return
                }
                $max_len = ($PSCompletions.list | Measure-Object -Maximum Length).Maximum
                foreach ($_ in $PSCompletions.list) {
                    $status = if ($PSCompletions.cmd.$_) { $PSCompletions.info.list.added_symbol }else { $PSCompletions.info.list.add_symbol }
                    $data.Add(@{
                            content = "{0,-$($max_len + 3)} {1}" -f ($_, $status)
                            color   = 'Green'
                        })
                }
                $PSCompletions.show_with_less_table($data, ('Completion', 'Status', $max_len), {
                        $PSCompletions.write_with_color((_replace $PSCompletions.info.list.symbol_tip))
                    })
            }
            else {
                Show-ParamError 'err' 'list'
            }
        }
        else {
            Show-List
        }
    }
    function _add {
        if ($arg.Length -lt 2) {
            Show-ParamError 'min' 'add'
            return
        }
        if (!($PSCompletions.download_list())) {
            $PSCompletions.write_with_color((_replace $PSCompletions.info.err.download_list))
            return
        }

        if ($arg.Length -eq 2 -and $arg[1] -eq '*') {
            foreach ($_ in $PSCompletions.list) {
                $PSCompletions.add_completion($_)
            }
            return
        }
        foreach ($completion in $arg[1..($arg.Length - 1)]) {
            if ($completion -in $PSCompletions.list) {
                $PSCompletions.add_completion($completion)
            }
            else {
                $PSCompletions.write_with_color((_replace $PSCompletions.info.add.err.no))
            }
        }
    }
    function _rm {
        if ($arg.Length -lt 2) {
            Show-ParamError 'min' 'rm'
            return
        }
        Clear-Content $PSCompletions.path.update -Force
        $PSCompletions.update = @()

        if ($arg.Length -eq 2 -and $arg[1] -eq '*') {
            foreach ($completion in $PSCompletions.cmd.keys) {
                $dir = Join-Path $PSCompletions.path.completions $completion
                Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
                if (!(Test-Path $dir)) {
                    $PSCompletions.write_with_color((_replace $PSCompletions.info.rm.done))
                }
            }
            return
        }

        foreach ($completion in  $arg[1..($arg.Length - 1)]) {
            if ($completion -in $PSCompletions.cmd.keys) {
                $dir = Join-Path $PSCompletions.path.completions $completion
                if (!(Test-Path $dir)) {
                    $PSCompletions.write_with_color((_replace $PSCompletions.info.no_completion))
                    continue
                }
                Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
                if (!(Test-Path $dir)) {
                    $PSCompletions.write_with_color((_replace $PSCompletions.info.rm.done))
                }
            }
            else { $PSCompletions.write_with_color((_replace $PSCompletions.info.no_completion)) }
        }
    }
    function _update {
        $completion_list = $PSCompletions.cmd.keys.Where({ $_ -in $PSCompletions.list })

        if ($arg.Length -lt 2) {
            # 如果只是使用 psc update 则检查更新
            $need_update_list = [System.Collections.Generic.List[string]]@()
            foreach ($completion in $completion_list) {
                try {
                    $response = Invoke-WebRequest -Uri "$($PSCompletions.url)/completions/$($completion)/guid.txt"
                    $content = $response.Content.Trim()
                    $guid = $PSCompletions.get_raw_content("$($PSCompletions.path.completions)/$($completion)/guid.txt")
                    if ($guid -ne $content -and $content -match "^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$") { $need_update_list.Add($completion) }
                }
                catch {  }
            }
            $PSCompletions.update = $need_update_list
        }
        else {
            $updated_list = [System.Collections.Generic.List[string]]@()
            if ($arg[1] -eq '*') {
                # 更新全部可以更新的补全
                foreach ($_ in $PSCompletions.update) {
                    $PSCompletions.add_completion($_, $true)
                    $updated_list.Add($_)
                }
            }
            else {
                foreach ($completion in $arg[1..($arg.Length - 1)]) {
                    if ($completion -in $completion_list) {
                        $PSCompletions.add_completion($completion, $true)
                        $updated_list.Add($completion)
                    }
                    else {
                        $PSCompletions.write_with_color((_replace $PSCompletions.info.no_completion))
                    }
                }
            }
            $PSCompletions.update = $PSCompletions.get_content($PSCompletions.path.update).Where({ $_ -notin $updated_list })
        }

        if ($PSCompletions.update) {
            $PSCompletions.write_with_color((_replace $PSCompletions.info.update_has))
        }
        else {
            $PSCompletions.write_with_color((_replace $PSCompletions.info.update_no))
        }
        $PSCompletions.update | Out-File $PSCompletions.path.update -Force -Encoding utf8
    }
    function _search {
        if ($arg.Length -lt 2) {
            Show-ParamError 'min' 'search'
            return
        }
        if ($arg.Length -gt 2) {
            Show-ParamError 'max' 'search'
            return
        }
        if (!($PSCompletions.download_list())) {
            $PSCompletions.write_with_color((_replace $PSCompletions.info.err.download_list))
            return
        }
        $result = $PSCompletions.list.Where({ $_ -like $arg[1] })
        if ($result) {
            $PSCompletions.show_with_less($result, 'Cyan')
        }
        else {
            $PSCompletions.write_with_color((_replace $PSCompletions.info.search.err.no))
        }
    }
    function _which {
        if ($arg.Length -lt 2) {
            Show-ParamError 'min' 'which'
            return
        }
        foreach ($completion in $arg[1..($arg.Length - 1)]) {
            if ($completion -in $PSCompletions.cmd.keys) {
                Write-Output (Join-Path $PSCompletions.path.completions $completion)
            }
            else {
                $PSCompletions.write_with_color((_replace $PSCompletions.info.no_completion))
            }
        }
    }
    function _alias {
        $cmd_list = @('list', 'add', 'rm')
        if ($arg.Length -lt 2) {
            Show-ParamError 'min' '' $PSCompletions.info.sub_cmd
            return
        }
        if ($arg[1] -notin $cmd_list) {
            $sub_cmd = $arg[1]
            Show-ParamError 'err' '' $PSCompletions.info.sub_cmd
            return
        }
        switch ($arg[1]) {
            'list' {
                if ($arg[2]) {
                    Show-ParamError 'max' '' '' $PSCompletions.info.alias.list.example
                    return
                }
                $data = [System.Collections.Generic.List[System.Object]]@()
                Show-List
            }
            'add' {
                $completion = $arg[2]
                if ($arg[2] -eq $null) {
                    $cmd_list = $PSCompletions.cmd.keys
                    Show-ParamError 'min' '' $PSCompletions.info.sub_cmd $PSCompletions.info.alias.add.example
                    return
                }
                else {
                    if ($arg[2] -notin $PSCompletions.cmd.Keys) {
                        Show-ParamError 'err' '' $PSCompletions.info.no_completion
                        return
                    }
                }
                if ($arg[3] -eq $null) {
                    Show-ParamError 'min' '' $PSCompletions.info.alias.add.err.min_v $PSCompletions.info.alias.add.example
                    return
                }
                foreach ($alias in $arg[3..($arg.Length - 1)]) {
                    $alias = ($alias -split ' ')[0]
                    if (Get-Command $alias -ErrorAction SilentlyContinue) {
                        Show-ParamError 'err' '' $PSCompletions.info.alias.add.err.cmd_exist
                        return
                    }
                    $path_alias = "$($PSCompletions.path.completions)/$($completion)/alias.txt"
                    $alias_list = $PSCompletions.get_content($path_alias)
                    if ($alias -notin $alias_list) {
                        $alias | Out-File $path_alias -Append -Encoding utf8 -Force
                        $PSCompletions.write_with_color((_replace $PSCompletions.info.alias.done))
                    }
                    else {
                        Show-ParamError 'err' '' $PSCompletions.info.alias.add.err.exist
                    }
                }
            }
            'rm' {
                $completion = $arg[2]
                if ($arg[2] -eq $null) {
                    $cmd_list = $PSCompletions.cmd.keys
                    Show-ParamError 'min' '' $PSCompletions.info.sub_cmd $PSCompletions.info.alias.rm.example
                    return
                }
                else {
                    if ($arg[2] -notin $PSCompletions.cmd.Keys) {
                        Show-ParamError 'err' '' $PSCompletions.info.no_completion
                        return
                    }
                }
                if ($arg[3] -eq $null) {
                    Show-ParamError 'min' '' $PSCompletions.info.alias.rm.err.min_v $PSCompletions.info.alias.rm.example
                    return
                }

                foreach ($alias in $arg[3..($arg.Length - 1)]) {
                    if ($alias -in $PSCompletions.alias.Keys) {
                        $path_alias = "$($PSCompletions.path.completions)/$($PSCompletions.alias.$alias)/alias.txt"
                        $alias_list = $PSCompletions.get_content($path_alias)
                        if ($alias_list.Count -gt 1) {
                            $alias_list.Where({ $_ -ne $alias }) | Out-File $path_alias -Force -Encoding utf8
                            $PSCompletions.write_with_color((_replace $PSCompletions.info.alias.done))
                        }
                        else {
                            $PSCompletions.write_with_color((_replace ($PSCompletions.info.alias.rm.err.unique)))
                        }
                    }
                    else {
                        $PSCompletions.write_with_color((_replace ($PSCompletions.info.alias.rm.err.no_alias)))
                    }
                }
            }
        }
    }
    function _config {
        $cmd_list = @('language', 'disable_cache', 'update', 'module_update', 'symbol', 'github', 'gitee', 'url', 'function_name')
        if ($arg.Length -lt 2) {
            Show-ParamError 'min' '' $PSCompletions.info.sub_cmd  $PSCompletions.info.config.example
            return
        }

        if ($arg[1] -notin $cmd_list) {
            $sub_cmd = $arg[1]
            Show-ParamError 'err' '' $PSCompletions.info.sub_cmd
            return
        }

        if ($arg[1] -in $cmd_list) {
            if ($arg.Length -gt 3) {
                Show-ParamError 'max' '' $PSCompletions.info.config.$($arg[1]).err.max $PSCompletions.info.config.$($arg[1]).example
                return
            }
            if ($arg.Length -eq 2) {
                Write-Output $PSCompletions.config.$($arg[1])
            }
        }

        function handle_done {
            param([bool]$is_can, [switch]$common_err)
            if ($arg.Length -eq 3) {
                if ($is_can) {
                    $config_item = $arg[1]
                    $old_value = $PSCompletions.config.$($arg[1])
                    $new_value = $arg[2]
                    $PSCompletions.set_config($arg[1], $arg[2])
                    $PSCompletions.write_with_color((_replace $PSCompletions.info.config.done))
                }
                else {
                    if ($common_err) {
                        Show-ParamError 'err' '' $PSCompletions.info.config.err.value $PSCompletions.info.config.$($arg[1]).example
                    }
                    else {
                        Show-ParamError 'err' '' $PSCompletions.info.config.$($arg[1]).err.max $PSCompletions.info.config.$($arg[1]).example
                    }
                }
            }
        }
        $config_item = $arg[1]
        switch ($arg[1]) {
            'language' {
                handle_done ($arg[2] -is [string] -and $arg[2] -ne '')
            }
            'disable_cache' {
                handle_done ($arg[2] -is [int] -and $arg[2] -in @(1, 0)) -common_err
            }
            'update' {
                handle_done ($arg[2] -is [int] -and $arg[2] -in @(1, 0)) -common_err
            }
            'module_update' {
                handle_done ($arg[2] -is [int] -and $arg[2] -in @(1, 0)) -common_err
            }
            'github' {
                handle_done ($arg[2] -match 'http[s]?://github.com/.*' -or $arg[2] -eq '')
            }
            'gitee' {
                handle_done ($arg[2] -match 'http[s]?://gitee.com/.*' -or $arg[2] -eq '')
            }
            'url' {
                handle_done ($arg[2] -match 'http[s]?://' -or $arg[2] -eq '')
            }
            'function_name' {
                # Get-Command PSCompletions 会导致触发更新，需要特殊处理
                if ($arg[2] -eq 'PSCompletions' -and $PSCompletions.config.function_name -ne 'PSCompletions') {
                    handle_done $true
                    return
                }
                $is_exist = Get-Command $arg[2] -ErrorAction SilentlyContinue
                handle_done ($arg[2] -is [string] -and $arg[2] -ne '' -and !$is_exist)
            }
        }
    }
    function _completion {
        $cmd_list = $PSCompletions.cmd.keys
        if ($arg.Length -lt 2) {
            Show-ParamError 'min' '' $PSCompletions.info.sub_cmd $PSCompletions.info.completion.example
            return
        }
        if ($arg[1] -notin $PSCompletions.cmd.keys) {
            $cmd_list = $PSCompletions.cmd.keys
            $sub_cmd = $arg[1]
            Show-ParamError 'err' '' $PSCompletions.info.sub_cmd
            return
        }
        if ($arg.Length -lt 3) {
            Show-ParamError 'min' 'completion'
            return
        }
        # 每个补全都默认带有的两个配置项
        $config_list = @('language', 'menu_show_tip')

        if ($arg[2] -notin $config_list -and $PSCompletions.config.comp_config.$($arg[1]).$($arg[2]) -eq $null) {
            $cmd_list = $config_list + ($PSCompletions.config.comp_config.$($arg[1]).keys.Where({ $_ -notin $config_list }))
            $sub_cmd = $arg[2]
            Show-ParamError 'err' '' $PSCompletions.info.sub_cmd
            return
        }
        if ($arg.Length -gt 4) {
            Show-ParamError 'max' 'completion'
            return
        }
        if ($arg.Length -eq 3) {
            Write-Output $PSCompletions.config.comp_config.$($arg[1]).$($arg[2])
            return
        }
        if ($PSCompletions.config.comp_config.$($arg[1]) -eq $null) {
            $PSCompletions.config.comp_config.$($arg[1]) = @{}
        }

        $completion = $arg[1]
        $config_item = $arg[2]
        $old_value = $PSCompletions.config.comp_config.$($arg[1]).$($arg[2])
        $new_value = $arg[3]
        $PSCompletions.config.comp_config.$($arg[1]).$($arg[2]) = $arg[3]
        foreach ($_ in $PSCompletions.cmd.keys) {
            $path = "$($PSCompletions.path.completions)/$($_)/config.json"
            $json = $PSCompletions.get_raw_content($path) | ConvertFrom-Json
            $path = "$($PSCompletions.path.completions)/$($_)/language/$($json.language[0]).json"
            $json = $PSCompletions.ConvertFrom_JsonToHashtable($PSCompletions.get_raw_content($path))
            $config_list = @('language', 'menu_show_tip')
            if ($json.config) {
                foreach ($item in $json.config) {
                    $config_list += $item.name
                    if ($PSCompletions.config.comp_config.$_.$($item.name) -in @('', $null)) {
                        $PSCompletions.config.comp_config.$_.$($item.name) = $item.value
                    }
                }
            }
            try {
                foreach ($item in $PSCompletions.config.comp_config.keys) {
                    if ($item -notin $PSCompletions.list -and !(Test-Path "$($PSCompletions.path.completions)/$($item)")) {
                        $PSCompletions.config.comp_config.Remove($item)
                    }
                    foreach ($c in $PSCompletions.config.comp_config.$item.keys) {
                        if ($c -notin $config_list) {
                            $PSCompletions.config.comp_config.$item.Remove($c)
                        }
                        if ($c -in @('language', 'menu_show_tip') -and $PSCompletions.config.comp_config.$item.$c -in @('', $null)) {
                            $PSCompletions.config.comp_config.$item.Remove($c)
                        }
                    }
                }
            }
            catch {}
        }
        Out-Config
        $PSCompletions.write_with_color((_replace $PSCompletions.info.completion.done))
    }
    function _menu {
        $cmd_list = @('symbol', 'line_theme', 'color_theme', 'custom', 'config')
        if ($arg.Length -lt 2) {
            Show-ParamError 'min' 'menu' $PSCompletions.info.sub_cmd
            return
        }
        if ($arg[1] -notin $cmd_list) {
            Show-ParamError 'err' 'menu' $PSCompletions.info.sub_cmd
        }
        switch ($arg[1]) {
            'symbol' {
                $cmd_list = @('SpaceTab', 'WriteSpaceTab', 'OptionTab')
                if ($arg.Length -eq 2) {
                    Show-ParamError 'min' '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.$($arg[1]).example
                    return
                }
                if ($arg[2] -notin $cmd_list) {
                    $sub_cmd = $arg[2]
                    Show-ParamError 'err' '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.$($arg[1]).example
                }
                if ($arg.Length -gt 4) {
                    Show-ParamError 'max' '' $PSCompletions.info.menu.$($arg[1]).err.max $PSCompletions.info.menu.$($arg[1]).example
                    return
                }
                if ($arg.Length -eq 3) {
                    Write-Output $PSCompletions.config."symbol_$($arg[2])"
                }
                if ($arg.Length -eq 4) {
                    $config_item = "$($arg[1]) $($arg[2])"
                    $old_value = $PSCompletions.config."symbol_$($arg[2])"
                    $new_value = $arg[3]
                    $PSCompletions.set_config("symbol_$($arg[2])", $arg[3])
                    $PSCompletions.write_with_color((_replace $PSCompletions.info.menu.done))
                }
            }
            'line_theme' {
                $cmd_list = @('double_line_rect_border', 'single_line_rect_border', 'single_line_round_border')
                if ($arg.Length -lt 3) {
                    Show-ParamError 'min' '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.line_theme.example
                    return
                }
                if ($arg[2] -notin $cmd_list) {
                    Show-ParamError 'err' '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.line_theme.example
                    return
                }
                if ($arg.Length -gt 3) {
                    Show-ParamError 'max' '' '' $PSCompletions.info.menu.line_theme.example
                    return
                }
                switch ($arg[2]) {
                    'double_line_rect_border' {
                        $PSCompletions.config.menu_line_horizontal = [string][char]9552
                        $PSCompletions.config.menu_line_vertical = [string][char]9553
                        $PSCompletions.config.menu_line_top_left = [string][char]9556
                        $PSCompletions.config.menu_line_bottom_left = [string][char]9562
                        $PSCompletions.config.menu_line_top_right = [string][char]9559
                        $PSCompletions.config.menu_line_bottom_right = [string][char]9565
                    }
                    'single_line_rect_border' {
                        $PSCompletions.config.menu_line_horizontal = [string][char]9472
                        $PSCompletions.config.menu_line_vertical = [string][char]9474
                        $PSCompletions.config.menu_line_top_left = [string][char]9484
                        $PSCompletions.config.menu_line_bottom_left = [string][char]9492
                        $PSCompletions.config.menu_line_top_right = [string][char]9488
                        $PSCompletions.config.menu_line_bottom_right = [string][char]9496
                    }
                    'single_line_round_border' {
                        $PSCompletions.config.menu_line_horizontal = [string][char]9472
                        $PSCompletions.config.menu_line_vertical = [string][char]9474
                        $PSCompletions.config.menu_line_top_left = [string][char]9581
                        $PSCompletions.config.menu_line_bottom_left = [string][char]9584
                        $PSCompletions.config.menu_line_top_right = [string][char]9582
                        $PSCompletions.config.menu_line_bottom_right = [string][char]9583
                    }
                }
                Out-Config
                $PSCompletions.write_with_color((_replace $PSCompletions.info.menu.line_theme.done))
            }
            'color_theme' {
                $cmd_list = @('default', 'magenta')
                if ($arg.Length -lt 3) {
                    Show-ParamError 'min' '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.color_theme.example
                    return
                }

                if ($arg[2] -notin $cmd_list) {
                    Show-ParamError 'err' '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.color_theme.example
                    return
                }
                if ($arg.Length -gt 3) {
                    Show-ParamError 'max' '' '' $PSCompletions.info.menu.color_theme.example
                    return
                }
                switch ($arg[2]) {
                    'magenta' {
                        $PSCompletions.config.menu_color_item_text = 'Magenta'
                        $PSCompletions.config.menu_color_item_back = 'White'
                        $PSCompletions.config.menu_color_selected_text = 'white'
                        $PSCompletions.config.menu_color_selected_back = 'DarkMagenta'
                        $PSCompletions.config.menu_color_filter_text = 'Magenta'
                        $PSCompletions.config.menu_color_filter_back = 'White'
                        $PSCompletions.config.menu_color_border_text = 'Magenta'
                        $PSCompletions.config.menu_color_border_back = 'White'
                        $PSCompletions.config.menu_color_status_text = 'Magenta'
                        $PSCompletions.config.menu_color_status_back = 'White'
                        $PSCompletions.config.menu_color_tip_text = 'Magenta'
                        $PSCompletions.config.menu_color_tip_back = 'White'
                    }
                    'default' {
                        $PSCompletions.config.menu_color_item_text = 'Blue'
                        $PSCompletions.config.menu_color_item_back = 'Black'
                        $PSCompletions.config.menu_color_selected_text = 'white'
                        $PSCompletions.config.menu_color_selected_back = 'DarkGray'
                        $PSCompletions.config.menu_color_filter_text = 'Yellow'
                        $PSCompletions.config.menu_color_filter_back = 'Black'
                        $PSCompletions.config.menu_color_border_text = 'DarkGray'
                        $PSCompletions.config.menu_color_border_back = 'Black'
                        $PSCompletions.config.menu_color_status_text = 'Blue'
                        $PSCompletions.config.menu_color_status_back = 'Black'
                        $PSCompletions.config.menu_color_tip_text = 'Cyan'
                        $PSCompletions.config.menu_color_tip_back = 'Black'
                    }
                }
                Out-Config
                $PSCompletions.write_with_color((_replace $PSCompletions.info.menu.color_theme.done))
            }
            'custom' {
                $cmd_list = @('color', 'line')
                if ($arg.Length -lt 3) {
                    Show-ParamError 'min' '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.custom.example
                    return
                }
                if ($arg[2] -notin $cmd_list) {
                    Show-ParamError 'err' '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.custom.example
                    return
                }
                if ($arg.Length -lt 4) {
                    $cmd_list = $PSCompletions.menu.const."$($arg[2])_item"
                    Show-ParamError 'min' '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.custom.example
                    return
                }
                if ($arg[3] -notin $PSCompletions.menu.const."$($arg[2])_item") {
                    $cmd_list = $PSCompletions.menu.const."$($arg[2])_item"
                    Show-ParamError 'err'  '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.custom.example
                    return
                }
                if ($arg.Length -lt 5) {
                    if ($arg[2] -eq 'color') {
                        $cmd_list = $PSCompletions.menu.const.color_value
                        Show-ParamError 'min' '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.custom.example
                        return
                    }
                    else {
                        Show-ParamError 'min' '' '' $PSCompletions.info.menu.custom.example
                    }
                }
                if ($arg.Length -gt 5) {
                    if ($arg[2] -eq 'color' -and $arg[4] -notin $PSCompletions.menu.const.color_value) {
                        $cmd_list = $PSCompletions.menu.const.color_value
                        Show-ParamError 'err' '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.custom.example
                        return
                    }
                }

                if ($arg[5]) {
                    Show-ParamError 'max' '' '' $PSCompletions.info.menu.custom.example
                    return
                }

                $config_item = "$($arg[2]) $($arg[3])"
                $old_value = $PSCompletions.config."menu_$($arg[2])_$($arg[3])"
                $new_value = $arg[4]
                $PSCompletions.set_config("menu_$($arg[2])_$($arg[3])", $arg[4])
                $PSCompletions.write_with_color((_replace $PSCompletions.info.menu.done))
            }
            'config' {
                $cmd_list = $PSCompletions.menu.const.config_item
                if ($arg.Length -lt 3) {
                    Show-ParamError 'min' '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.config.example
                    return
                }
                if ($arg[2] -notin $cmd_list) {
                    Show-ParamError 'err' '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.config.example
                    return
                }
                if ($arg.Length -eq 3) {
                    $PSCompletions.config.$($arg[2])
                    return
                }
                if ($arg.Length -gt 4) {
                    Show-ParamError 'max' '' '' $PSCompletions.info.menu.config.example
                    return
                }

                try {
                    $value = [int]$arg[3]
                    $is_num = $true
                }
                catch {
                    $value = $arg[3]
                    $is_num = $false
                }
                switch ($arg[2]) {
                    'menu_trigger_key' {
                        try {
                            $PSCompletions.config.menu_trigger_key = $arg[3]
                            $PSCompletions.powershell_completion()
                            $PSCompletions.config.menu_trigger_key = "Tab"
                        }
                        catch {
                            Show-ParamError 'err' 'menu_trigger_key' $PSCompletions.info.menu.config.err.menu_trigger_key
                            $PSCompletions.config.menu_trigger_key = "Tab"
                            return
                        }
                    }

                    { $_ -in @('menu_above_list_max_count', 'menu_below_list_max_count') } {
                        $cmd_list = $null
                        $sub_cmd = $arg[3]
                        $cmd_info = $PSCompletions.info.menu.config.err.v_2
                        if (!$is_num -or ($arg[3] -ne -1 -and $arg[3] -le 0)) {
                            Show-ParamError 'err' '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.config.example
                            return
                        }
                    }
                    { $_ -in @('menu_above_margin_bottom', 'menu_list_min_width', 'menu_list_margin_left', 'menu_list_margin_right') } {
                        if (!$is_num -or $arg[3] -lt 0) {
                            $cmd_list = $null
                            $sub_cmd = $arg[3]
                            $cmd_info = $PSCompletions.info.menu.config.err.v_0
                            Show-ParamError 'err' '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.config.example
                            return
                        }
                    }
                    { $_ -in @('menu_enable', 'menu_show_tip', 'menu_list_follow_cursor', 'menu_tip_follow_cursor', 'menu_list_cover_buffer', 'menu_tip_cover_buffer', 'menu_is_prefix_match', 'menu_is_loop', 'menu_selection_with_margin', 'enter_when_single', 'menu_completions_sort', 'menu_enhance', 'menu_show_tip_when_enhance') } {
                        if (!$is_num -or $arg[3] -notin @(1, 0)) {
                            $cmd_list = $null
                            $sub_cmd = $arg[3]
                            $cmd_info = $PSCompletions.info.menu.config.err.v_3
                            Show-ParamError 'err' '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.config.example
                            return
                        }
                    }
                }
                $config_item = $arg[2]
                $old_value = $PSCompletions.config.$($arg[2])
                $new_value = $arg[3]
                $PSCompletions.set_config($arg[2], $arg[3])
                $PSCompletions.write_with_color((_replace $PSCompletions.info.menu.done))
            }
        }
    }
    function _reset {
        $cmd_list = @('env', 'alias', 'order', 'completion', 'menu', '*')
        if ($arg.Length -lt 2) {
            Show-ParamError 'min' '' $PSCompletions.info.sub_cmd $PSCompletions.info.reset.example
            return
        }
        if ($arg[1] -notin $cmd_list) {
            $sub_cmd = $arg[1]
            Show-ParamError 'err' '' $PSCompletions.info.sub_cmd $PSCompletions.info.reset.example
        }

        if ($arg[1] -in @('alias', 'completion', 'menu')) {
            $cmd_list = @('*')
            if ($arg[1] -in @('alias', 'completion')) {
                $cmd_list += $PSCompletions.cmd.Keys
            }
            elseif ($arg[1] -eq 'menu') {
                $cmd_list += @('symbol', 'line', 'color', 'config')
            }
            if ($arg.Length -eq 2) {
                Show-ParamError 'min' '' $PSCompletions.info.sub_cmd $PSCompletions.info.reset.$($arg[1]).example
                return
            }
            if ($arg[1] -ne 'completion' -and $arg.Length -gt 3) {
                Show-ParamError 'max' '' '' $PSCompletions.info.reset.$($arg[1]).example
                return
            }
        }
        else {
            if ($arg.Length -ne 2) {
                $cmd_list = $null
                Show-ParamError 'max' '' '' $PSCompletions.info.reset.example
                return
            }
        }
        function handle_reset {
            param([string]$cmd)
            $change_list = [System.Collections.Generic.List[System.Object]]@()
            foreach ($_ in $PSCompletions.default.$cmd.Keys) {
                $change_list.Add(@{
                        item      = $_
                        old_value = $PSCompletions.config.$_
                        new_value = $PSCompletions.default.$cmd.$_
                    })
                $PSCompletions.config.$_ = $PSCompletions.default.$cmd.$_
            }
            # 返回修改后的信息
            return $change_list
        }
        $is_change_config = $true
        switch ($arg[1]) {
            'env' {
                $change_list = handle_reset $arg[1]
            }
            'alias' {
                $change_list = [System.Collections.Generic.List[System.Object]]@()
                $del_list = if ($arg[2] -eq '*') { $PSCompletions.cmd.Keys }else { $arg[2..($arg.Length - 1)] }

                foreach ($completion in $del_list) {
                    if ($completion -in $PSCompletions.cmd.Keys) {
                        $path_alias = "$($PSCompletions.path.completions)/$($completion)/alias.txt"
                        $old_value = $PSCompletions.get_content($path_alias) -join ' '
                        Set-Content -Path $path_alias -Value $completion -Force -Encoding utf8
                        $change_list.Add(@{
                                item      = $completion
                                old_value = $old_value
                                new_value = $completion
                            })
                    }
                    else {
                        $PSCompletions.write_with_color((_replace $PSCompletions.info.no_completion))
                    }
                }
                $is_change_config = $false
            }
            "order" {
                foreach ($_ in $PSCompletions.cmd.Keys) {
                    $path_order = "$($PSCompletions.path.completions)/$($_)/order.json"
                    Remove-Item $path_order -Force -ErrorAction SilentlyContinue
                }
                $change_list = $null
                $is_change_config = $false
            }
            "completion" {
                function _do {
                    param([string]$cmd, [switch]$is_all)
                    $path = "$($PSCompletions.path.completions)/$($cmd)/config.json"
                    $json = $PSCompletions.get_raw_content($path) | ConvertFrom-Json
                    $path = "$($PSCompletions.path.completions)/$($cmd)/language/$($json.language[0]).json"
                    $json = $PSCompletions.ConvertFrom_JsonToHashtable($PSCompletions.get_raw_content($path))
                    if ($json.config) {
                        foreach ($item in $json.config) {
                            if (!$PSCompletions.config.comp_config.$cmd) {
                                $PSCompletions.config.comp_config.$cmd = @{}
                            }
                            if ($is_all) {
                                $PSCompletions.config.comp_config.$cmd.$($item.name) = $item.value
                            }
                            else {
                                if ($PSCompletions.config.comp_config.$cmd.$($item.name) -in @('', $null)) {
                                    $PSCompletions.config.comp_config.$cmd.$($item.name) = $item.value
                                }
                            }
                        }
                    }
                }
                if ($arg[2] -eq '*') {
                    $PSCompletions.config.comp_config = @{}
                    foreach ($_ in $PSCompletions.cmd.keys) {
                        _do $_ -is_all
                    }
                }
                else {
                    if ($arg.Length -eq 3) {
                        $PSCompletions.config.comp_config.$($arg[2]) = @{}
                    }
                    else {
                        # great than 3
                        $config_list = $arg[3..($arg.Length - 1)]
                        if (!$PSCompletions.config.comp_config.$($arg[2])) {
                            $PSCompletions.config.comp_config.$($arg[2]) = @{}
                        }
                        foreach ($config in $config_list) {
                            try { $PSCompletions.config.comp_config.$($arg[2]).Remove($config) }catch {}
                        }
                    }
                    _do $arg[2]
                }
            }
            "menu" {
                $cmd_list = @('*', 'symbol', 'line', 'color', 'config')
                if ($arg[2] -notin $cmd_list) {
                    $sub_cmd = $arg[2]
                    Show-ParamError 'min' '' $PSCompletions.info.sub_cmd $PSCompletions.info.reset.example
                    return
                }
                switch ($arg[2]) {
                    'symbol' {
                        $change_list = handle_reset 'symbol'
                    }
                    'line' {
                        $change_list = handle_reset 'menu_line'
                    }
                    'color' {
                        $change_list = handle_reset 'menu_color'
                    }
                    'config' {
                        $change_list = handle_reset 'menu_config'
                    }
                    '*' {
                        $change_list = [System.Collections.Generic.List[System.Object]]@()
                        $change_list += handle_reset 'symbol'
                        $change_list += handle_reset 'menu_line'
                        $change_list += handle_reset 'menu_color'
                        $change_list += handle_reset 'menu_config'
                    }
                }
            }
            '*' {
                $is_init_module = $PSCompletions.confirm_do($PSCompletions.replace_content($PSCompletions.info.reset.init_confirm), {
                        foreach ($_ in @('completions', 'completions_json', 'config', 'update', 'change')) {
                            Remove-Item $PSCompletions.path.$_ -Force -Recurse -ErrorAction SilentlyContinue
                        }
                        Remove-Item "$($PSCompletions.path.core)/CHANGELOG.json" -Force -Recurse -ErrorAction SilentlyContinue
                    })
                if ($is_init_module) {
                    $PSCompletions.write_with_color((_replace $PSCompletions.info.reset.init_done))
                }
                else {
                    $no_show_msg = $true
                }
            }
        }
        if ($is_change_config) { Out-Config }
        if (!$no_show_msg) { $PSCompletions.write_with_color((_replace $PSCompletions.info.reset.done)) }
    }
    function _help {
        $json = $PSCompletions.data.psc
        $info = $PSCompletions.info
        $PSCompletions.write_with_color((_replace $PSCompletions.info.description))
    }
    $need_init = $true
    switch ($arg[0]) {
        'list' {
            _list
            $need_init = $false
        }
        'add' {
            _add
        }
        'rm' {
            _rm
        }
        'update' {
            _update
        }
        'search' {
            _search
            $need_init = $false
        }
        'which' {
            _which
            $need_init = $false
        }
        'alias' {
            _alias
        }
        'config' {
            _config
        }
        'completion' {
            _completion
        }
        'menu' {
            _menu
        }
        'reset' {
            _reset
        }
        default {
            if ($arg[0]) {
                $sub_cmd = $arg[0]
                $cmd_list = @('list', 'add', 'rm', 'update', 'search', 'which', 'alias', 'config', 'completion', 'menu', 'reset')
                $PSCompletions.write_with_color((_replace $PSCompletions.info.sub_cmd))
            }
            else { _help }
        }
    }
    if ($need_init) { $PSCompletions.init_data() }
} -Option ReadOnly

Export-ModuleMember -Function $PSCompletions.config.function_name
