﻿Set-Item -Path Function:$($PSCompletions.config.function_name) -Value {
    $arg = $args

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
        $max_len = ($PSCompletions.data.list | Measure-Object -Maximum Length).Maximum
        $max_len = [Math]::Max($max_len, 10)
        foreach ($_ in $PSCompletions.data.list) {
            $alias = $PSCompletions.data.alias.$_ -join ' '
            $data.Add(@{
                    content = "{0,-$($max_len + 3)} {1}" -f ($_, $alias)
                    color   = 'Green'
                })
        }
        $PSCompletions.show_with_less_table($data, ('Completion', 'Alias', $max_len))
    }
    function Out-Data {
        if ($PSCompletions._need_update_data) {
            $PSCompletions.data | ConvertTo-Json -Depth 100 -Compress | Out-File $PSCompletions.path.data -Force -Encoding utf8
            $PSCompletions._need_update_data = $null
        }
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
                    $PSCompletions._invalid_url = $null
                    return
                }
                $max_len = ($PSCompletions.list | Measure-Object -Maximum Length).Maximum
                foreach ($_ in $PSCompletions.list) {
                    $status = if ($PSCompletions.data.alias.$_) { $PSCompletions.info.list.added_symbol }else { $PSCompletions.info.list.add_symbol }
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
            $PSCompletions._invalid_url = $null
            return
        }

        if ($arg.Length -eq 2 -and $arg[1] -eq '*') {
            foreach ($_ in $PSCompletions.list) {
                $PSCompletions.add_completion($_)
                $PSCompletions._need_update_data = $true
            }
            return
        }
        $completions_list = $arg[1..($arg.Length - 1)]
        foreach ($completion in $completions_list) {
            if ($completion -in $PSCompletions.list) {
                $PSCompletions.add_completion($completion)
                $PSCompletions._need_update_data = $true
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

        $data = [ordered]@{
            list     = @()
            alias    = [ordered]@{}
            aliasMap = [ordered]@{}
            config   = $PSCompletions.data.config
        }

        if ($arg.Length -eq 2 -and $arg[1] -eq '*') {
            foreach ($completion in $PSCompletions.data.list) {
                $dir = Join-Path $PSCompletions.path.completions $completion
                Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
                if (!(Test-Path $dir)) {
                    $PSCompletions.write_with_color((_replace $PSCompletions.info.rm.done))
                }
            }

            $data.config.comp_config = @{}
        }
        else {
            $remove_list = @()
            foreach ($completion in  $arg[1..($arg.Length - 1)]) {
                if ($completion -in $PSCompletions.data.list) {
                    $remove_list += $completion
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
            foreach ($completion in $PSCompletions.data.list.Where({ $_ -notin $remove_list })) {
                $data.list += $completion
            }
            foreach ($_ in $data.list) {
                $data.alias.$_ = @()
                if ($PSCompletions.data.alias.$_) {
                    foreach ($a in $PSCompletions.data.alias.$_) {
                        $data.alias.$_ += $a
                        $data.aliasMap.$a = $_
                    }
                }
                else {
                    $data.alias.$_ += $_
                    $data.aliasMap.$_ = $_
                }
            }
        }
        $data | ConvertTo-Json -Depth 100 -Compress | Out-File $PScompletions.path.data -Force -Encoding utf8
        $PSCompletions.data = $data
    }
    function _update {
        $completion_list = $PSCompletions.data.list.Where({ $_ -in $PSCompletions.list })

        if ($arg.Length -lt 2) {
            # 如果只是使用 psc update 则检查更新
            $need_update_list = [System.Collections.Generic.List[string]]@()
            foreach ($completion in $completion_list) {
                try {
                    $response = Invoke-WebRequest -Uri "$($PSCompletions.url)/completions/$completion/guid.txt"
                    $content = $response.Content.Trim()
                    $guid = $PSCompletions.get_raw_content("$($PSCompletions.path.completions)/$completion/guid.txt")
                    if ($guid -ne $content -and $content -match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$') { $need_update_list.Add($completion) }
                }
                catch {  }
            }
            $PSCompletions.update = $need_update_list
        }
        else {
            $updated_list = [System.Collections.Generic.List[string]]@()
            if ($arg[1] -eq '*') {
                foreach ($_ in $PSCompletions.update) {
                    $PSCompletions.add_completion($_)
                    $PSCompletions._need_update_data = $true
                    $updated_list.Add($_)
                }
            }
            else {
                foreach ($completion in $arg[1..($arg.Length - 1)]) {
                    if ($completion -in $completion_list) {
                        $PSCompletions.add_completion($completion)
                        $PSCompletions._need_update_data = $true
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
            $PSCompletions._invalid_url = $null
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
            if ($completion -in $PSCompletions.data.list) {
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

        if ($arg[1] -eq 'list') {
            if ($arg[2]) {
                Show-ParamError 'max' '' '' $PSCompletions.info.alias.list.example
                return
            }
            $data = [System.Collections.Generic.List[System.Object]]@()
            Show-List
            return
        }

        $data_alias = [ordered]@{}
        $data_aliasMap = [ordered]@{}
        foreach ($_ in $PSCompletions.data.list) {
            $data_alias.$_ = [System.Collections.Generic.List[string]]@()
            if ($PSCompletions.data.alias.$_) {
                foreach ($a in $PSCompletions.data.alias.$_) {
                    $data_alias.$_.Add($a)
                    $data_aliasMap.$a = $_
                }
            }
            else {
                $data_alias.$_.Add($_)
                $data_aliasMap.$_ = $_
            }
        }
        switch ($arg[1]) {
            'add' {
                $completion = $arg[2]
                if ($arg[2] -eq $null) {
                    $cmd_list = $PSCompletions.data.list
                    Show-ParamError 'min' '' $PSCompletions.info.sub_cmd $PSCompletions.info.alias.add.example
                    return
                }
                else {
                    if ($arg[2] -notin $PSCompletions.data.list) {
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
                    if ($alias -in $data_alias.$completion) {
                        Show-ParamError 'err' '' $PSCompletions.info.alias.add.err.exist
                        return
                    }
                    if (Get-Command $alias -ErrorAction SilentlyContinue) {
                        Show-ParamError 'err' '' $PSCompletions.info.alias.add.err.cmd_exist
                        return
                    }
                    $data_alias.$completion.Add($alias)
                    $data_aliasMap.$alias = $completion
                    $PSCompletions.write_with_color((_replace $PSCompletions.info.alias.done))
                }
            }
            'rm' {
                $completion = $arg[2]
                if ($arg[2] -eq $null) {
                    $cmd_list = $PSCompletions.data.list
                    Show-ParamError 'min' '' $PSCompletions.info.sub_cmd $PSCompletions.info.alias.rm.example
                    return
                }
                else {
                    if ($arg[2] -notin $PSCompletions.data.list) {
                        Show-ParamError 'err' '' $PSCompletions.info.no_completion
                        return
                    }
                }
                if ($arg[3] -eq $null) {
                    Show-ParamError 'min' '' $PSCompletions.info.alias.rm.err.min_v $PSCompletions.info.alias.rm.example
                    return
                }

                foreach ($alias in $arg[3..($arg.Length - 1)]) {
                    if ($alias -in $PSCompletions.data.aliasMap.Keys) {
                        if ($data_alias.$completion.Count -gt 1) {
                            $null = $data_alias.$completion.Remove($alias)
                            $null = $data_aliasMap.Remove($alias)
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
        $PSCompletions.data.alias = $data_alias
        $PSCompletions.data.aliasMap = $data_aliasMap
        $PSCompletions.data | ConvertTo-Json -Depth 100 -Compress | Out-File $PScompletions.path.data -Force -Encoding utf8
    }
    function _config {
        $cmd_list = $PSCompletions.config_item
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
                    $old_value = $PSCompletions.config.$config_item
                    $new_value = $arg[2]
                    $PSCompletions.config.$config_item = $new_value
                    $PSCompletions._need_update_data = $true
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
            'enable_completions_update' {
                handle_done ($arg[2] -is [int] -and $arg[2] -in @(1, 0)) -common_err
            }
            'enable_module_update' {
                handle_done ($arg[2] -is [int] -and $arg[2] -in @(1, 0)) -common_err
            }
            'url' {
                handle_done ($arg[2] -match 'http[s]?://' -or $arg[2] -eq '')
            }
            'function_name' {
                handle_done ($arg[2] -ne '' -and !(Get-Command $arg[2] -ErrorAction SilentlyContinue))
            }
        }
    }
    function _completion {
        $cmd_list = $PSCompletions.data.list
        if ($arg.Length -lt 2) {
            Show-ParamError 'min' '' $PSCompletions.info.sub_cmd $PSCompletions.info.completion.example
            return
        }
        if ($arg[1] -notin $PSCompletions.data.list) {
            $cmd_list = $PSCompletions.data.list
            $sub_cmd = $arg[1]
            Show-ParamError 'err' '' $PSCompletions.info.sub_cmd
            return
        }
        if ($arg.Length -lt 3) {
            Show-ParamError 'min' 'completion'
            return
        }
        $config_list = $PSCompletions.default_completion_item

        if ($PSCompletions.config.comp_config.$($arg[1]) -eq $null) {
            $PSCompletions.config.comp_config.$($arg[1]) = @{}
        }

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

        $completion = $arg[1]
        $config_item = $arg[2]
        $old_value = $PSCompletions.config.comp_config.$completion.$config_item
        $new_value = $arg[3]
        $PSCompletions.config.comp_config.$completion.$config_item = $new_value
        $PSCompletions._need_update_data = $true
        foreach ($_ in $PSCompletions.data.list) {
            if (!$PSCompletions.config.comp_config.$_) {
                $PSCompletions.config.comp_config.$_ = @{}
            }
            $path = "$($PSCompletions.path.completions)/$_/config.json"
            $json = $PSCompletions.get_raw_content($path) | ConvertFrom-Json
            $path = "$($PSCompletions.path.completions)/$_/language/$($json.language[0]).json"
            $json = $PSCompletions.ConvertFrom_JsonToHashtable($PSCompletions.get_raw_content($path))
            $config_list = $PSCompletions.default_completion_item
            if ($json.config) {
                foreach ($item in $json.config) {
                    $config_list += $item.name
                    if ($PSCompletions.config.comp_config.$_.$($item.name) -in @('', $null)) {
                        $PSCompletions.config.comp_config.$_.$($item.name) = $item.value
                        $PSCompletions._need_update_data = $true
                    }
                }
            }
            if ($PSCompletions.config.comp_config.$_) {
                $_keys = @()
                foreach ($k in $PSCompletions.config.comp_config.$_.keys) {
                    if ($k -notin $config_list) {
                        $_keys += $k
                    }
                }
                foreach ($k in $_keys) {
                    $null = $PSCompletions.config.comp_config.$_.Remove($c)
                }
            }
        }
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
                $config_item = $arg[2]
                if ($arg.Length -eq 3) {
                    Write-Output $PSCompletions.config.$config_item
                }
                if ($arg.Length -eq 4) {
                    $old_value = $PSCompletions.config.$config_item
                    $new_value = $arg[3]
                    $PSCompletions.config.$config_item = $arg[3]
                    $PSCompletions._need_update_data = $true
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
                        $PSCompletions.config.horizontal = [string][char]9552
                        $PSCompletions.config.vertical = [string][char]9553
                        $PSCompletions.config.top_left = [string][char]9556
                        $PSCompletions.config.bottom_left = [string][char]9562
                        $PSCompletions.config.top_right = [string][char]9559
                        $PSCompletions.config.bottom_right = [string][char]9565
                    }
                    'single_line_rect_border' {
                        $PSCompletions.config.horizontal = [string][char]9472
                        $PSCompletions.config.vertical = [string][char]9474
                        $PSCompletions.config.top_left = [string][char]9484
                        $PSCompletions.config.bottom_left = [string][char]9492
                        $PSCompletions.config.top_right = [string][char]9488
                        $PSCompletions.config.bottom_right = [string][char]9496
                    }
                    'single_line_round_border' {
                        $PSCompletions.config.horizontal = [string][char]9472
                        $PSCompletions.config.vertical = [string][char]9474
                        $PSCompletions.config.top_left = [string][char]9581
                        $PSCompletions.config.bottom_left = [string][char]9584
                        $PSCompletions.config.top_right = [string][char]9582
                        $PSCompletions.config.bottom_right = [string][char]9583
                    }
                }
                $PSCompletions._need_update_data = $true
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
                        $PSCompletions.config.item_text = 'Magenta'
                        $PSCompletions.config.item_back = 'White'
                        $PSCompletions.config.selected_text = 'white'
                        $PSCompletions.config.selected_back = 'DarkMagenta'
                        $PSCompletions.config.filter_text = 'Magenta'
                        $PSCompletions.config.filter_back = 'White'
                        $PSCompletions.config.border_text = 'Magenta'
                        $PSCompletions.config.border_back = 'White'
                        $PSCompletions.config.status_text = 'Magenta'
                        $PSCompletions.config.status_back = 'White'
                        $PSCompletions.config.tip_text = 'Magenta'
                        $PSCompletions.config.tip_back = 'White'
                    }
                    'default' {
                        $PSCompletions.config.item_text = 'Blue'
                        $PSCompletions.config.item_back = 'Black'
                        $PSCompletions.config.selected_text = 'white'
                        $PSCompletions.config.selected_back = 'DarkGray'
                        $PSCompletions.config.filter_text = 'Yellow'
                        $PSCompletions.config.filter_back = 'Black'
                        $PSCompletions.config.border_text = 'DarkGray'
                        $PSCompletions.config.border_back = 'Black'
                        $PSCompletions.config.status_text = 'Blue'
                        $PSCompletions.config.status_back = 'Black'
                        $PSCompletions.config.tip_text = 'Cyan'
                        $PSCompletions.config.tip_back = 'Black'
                    }
                }
                $PSCompletions._need_update_data = $true
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
                $config_item = $arg[3]
                $old_value = $PSCompletions.config.$config_item
                $new_value = $arg[4]
                $PSCompletions.config.$config_item = $new_value
                $PSCompletions._need_update_data = $true
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
                    'trigger_key' {
                        try {
                            $PSCompletions.config.trigger_key = $arg[3]
                            $PSCompletions.powershell_completion()
                            $PSCompletions.config.trigger_key = 'Tab'
                        }
                        catch {
                            Show-ParamError 'err' 'trigger_key' $PSCompletions.info.menu.config.err.trigger_key
                            $PSCompletions.config.trigger_key = 'Tab'
                            return
                        }
                    }

                    { $_ -in @('list_max_count_when_above', 'list_max_count_when_below') } {
                        $cmd_list = $null
                        $sub_cmd = $arg[3]
                        $cmd_info = $PSCompletions.info.menu.config.err.v_2
                        if (!$is_num -or ($arg[3] -ne -1 -and $arg[3] -le 0)) {
                            Show-ParamError 'err' '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.config.example
                            return
                        }
                    }
                    { $_ -in @('list_min_width', 'width_from_menu_left_to_item', 'width_from_menu_right_to_item', 'height_from_menu_bottom_to_cursor_when_above') } {
                        if (!$is_num -or $arg[3] -lt 0) {
                            $cmd_list = $null
                            $sub_cmd = $arg[3]
                            $cmd_info = $PSCompletions.info.menu.config.err.v_0
                            Show-ParamError 'err' '' $PSCompletions.info.sub_cmd $PSCompletions.info.menu.config.example
                            return
                        }
                    }
                    { $_ -in ($PSCompletions.menu.const.config_item | Where-Object { $_ -match "(enable_*)|(disable_*)" }) } {
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
                $old_value = $PSCompletions.config.$config_item
                $new_value = $arg[3]
                $PSCompletions.config.$config_item = $new_value
                $PSCompletions._need_update_data = $true
                $PSCompletions.write_with_color((_replace $PSCompletions.info.menu.done))
            }
        }
    }
    function _reset {
        $cmd_list = @('config', 'alias', 'order', 'completion', 'menu', '*')
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
                $cmd_list += $PSCompletions.data.list
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
            param([array]$configs)
            $change_list = [System.Collections.Generic.List[System.Object]]@()
            foreach ($_ in $configs) {
                $change_list.Add(@{
                        item      = $_
                        old_value = $PSCompletions.config.$_
                        new_value = $PSCompletions.default_config.$_
                    })
                $PSCompletions.config.$_ = $PSCompletions.default_config.$_
                $PSCompletions._need_update_data = $true
            }
            return $change_list
        }
        switch ($arg[1]) {
            'config' {
                $change_list = handle_reset $PSCompletions.config_item
            }
            'alias' {
                $change_list = [System.Collections.Generic.List[System.Object]]@()
                $del_list = if ($arg[2] -eq '*') { $PSCompletions.data.list }else { $arg[2..($arg.Length - 1)] }

                foreach ($completion in $del_list) {
                    if ($completion -in $PSCompletions.data.list) {
                        $old_value = $PSCompletions.data.alias.$completion -join ' '
                        $PSCompletions.data.alias.Remove($completion)
                        $alias = ($PSCompletions.get_raw_content("$($PSCompletions.path.completions)/$completion/config.json") | ConvertFrom-Json).alias
                        $new_value = if ($alias) { $alias }else { @($completion) }
                        $PSCompletions.data.alias.$completion = $new_value
                        $PSCompletions._need_update_data = $true
                        $change_list.Add(@{
                                item      = $completion
                                old_value = $old_value
                                new_value = $new_value
                            })
                    }
                    else {
                        $PSCompletions.write_with_color((_replace $PSCompletions.info.no_completion))
                    }
                }
                $PSCompletions.data.aliasMap = [ordered]@{}
                foreach ($_ in $PSCompletions.data.list) {
                    if ($PSCompletions.data.alias.$_) {
                        foreach ($a in $PSCompletions.data.alias.$_) {
                            $PSCompletions.data.aliasMap.$a = $_
                            $PSCompletions._need_update_data = $true
                        }
                    }
                    else {
                        $PSCompletions.data.aliasMap.$_ = $_
                        $PSCompletions._need_update_data = $true
                    }
                }
            }
            'order' {
                foreach ($_ in $PSCompletions.data.list) {
                    $path_order = "$($PSCompletions.path.completions)/$_/order.json"
                    Remove-Item $path_order -Force -ErrorAction SilentlyContinue
                }
            }
            'completion' {
                function _do {
                    param([string]$cmd, [switch]$is_all)
                    $path = "$($PSCompletions.path.completions)/$cmd/config.json"
                    $json = $PSCompletions.get_raw_content($path) | ConvertFrom-Json
                    $path = "$($PSCompletions.path.completions)/$cmd/language/$($json.language[0]).json"
                    $json = $PSCompletions.ConvertFrom_JsonToHashtable($PSCompletions.get_raw_content($path))
                    foreach ($item in $json.config) {
                        if (!$PSCompletions.config.comp_config.$cmd) {
                            $PSCompletions.config.comp_config.$cmd = @{}
                        }
                        $PSCompletions._need_update_data = $true
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
                if ($arg[2] -eq '*') {
                    $PSCompletions.config.comp_config = @{}
                    foreach ($_ in $PSCompletions.data.list) {
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
                            try {
                                $PSCompletions.config.comp_config.$($arg[2]).Remove($config)
                                $PSCompletions._need_update_data = $true
                            }
                            catch {}
                        }
                    }
                    _do $arg[2]
                }
            }
            'menu' {
                $cmd_list = @('*', 'symbol', 'line', 'color', 'config')
                if ($arg[2] -notin $cmd_list) {
                    $sub_cmd = $arg[2]
                    Show-ParamError 'min' '' $PSCompletions.info.sub_cmd $PSCompletions.info.reset.example
                    return
                }
                switch ($arg[2]) {
                    'symbol' {
                        $change_list = handle_reset $PSCompletions.menu.const.symbol_item
                    }
                    'line' {
                        $change_list = handle_reset $PSCompletions.menu.const.line_item
                    }
                    'color' {
                        $change_list = handle_reset $PSCompletions.menu.const.color_item
                    }
                    'config' {
                        $change_list = handle_reset $PSCompletions.menu.const.config_item
                    }
                    '*' {
                        $change_list = [System.Collections.Generic.List[System.Object]]@()
                        $change_list += handle_reset $PSCompletions.menu.const.symbol_item
                        $change_list += handle_reset $PSCompletions.menu.const.line_item
                        $change_list += handle_reset $PSCompletions.menu.const.color_item
                        $change_list += handle_reset $PSCompletions.menu.const.config_item
                    }
                }
            }
            '*' {
                $is_init_module = $PSCompletions.confirm_do(
                    $PSCompletions.replace_content($PSCompletions.info.reset.init_confirm),
                    {
                        foreach ($_ in @('completions', 'completions_json', 'data' , 'update', 'change')) {
                            Remove-Item $PSCompletions.path.$_ -Force -Recurse -ErrorAction SilentlyContinue
                        }
                        Remove-Item "$($PSCompletions.path.core)/CHANGELOG.json" -Force -Recurse -ErrorAction SilentlyContinue
                    }
                )
                if ($is_init_module) {
                    $PSCompletions.write_with_color((_replace $PSCompletions.info.reset.init_done))
                }
                return
            }
        }
        $PSCompletions.write_with_color((_replace $PSCompletions.info.reset.done))
    }
    function _help {
        $json = $PSCompletions.completions.psc
        $info = $PSCompletions.info
        $PSCompletions.write_with_color((_replace $PSCompletions.info.description))
    }
    $need_init = $true
    $PSCompletions._need_update_data = $null
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
    Out-Data
    if ($need_init) { $PSCompletions.init_data() }
} -Option ReadOnly

Export-ModuleMember -Function $PSCompletions.config.function_name
