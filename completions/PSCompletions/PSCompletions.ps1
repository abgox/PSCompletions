Register-ArgumentCompleter -CommandName $PSCompletions.comp_cmd.PSCompletions -ScriptBlock {
    param($word_to_complete, $command_ast, $cursor_position)

    #region : Store
    $root_cmd = $PSCompletions.comp_cmd.PSCompletions

    $PSCompletions.fn_cache($PSScriptRoot, @('PSCompletions_core_info'))

    $completions = $PSCompletions.comp_data.$root_cmd.Clone()
    #endregion

    #region : Special
    $_i = 99999
    $PSCompletions.list | ForEach-Object {
        if ($_ -notin $PSCompletions.comp_cmd.keys) {
            $tip = $PSCompletions.fn_replace($PSCompletions.json.add)
            $completions[ $root_cmd + ' add ' + $_] = @($_, $tip, $_i)
        }
        $PSCompletions.comp_cmd.keys | ForEach-Object {
            $tip = $PSCompletions.fn_replace($PSCompletions.json.comp_tip)
            $completions[ $root_cmd + ' completion ' + $_] = @($_, $tip, $_i)

            $tip = $PSCompletions.fn_replace($PSCompletions.json.comp_lang)
            $completions[ $root_cmd + ' completion ' + $_ + ' language'] = @('language', $tip, $_i)
            $tip = $PSCompletions.fn_replace($PSCompletions.json.comp_lang_cn)
            $completions[ $root_cmd + ' completion ' + $_ + ' language zh-CN'] = @('zh-CN', $tip, $_i)
            $tip = $PSCompletions.fn_replace($PSCompletions.json.comp_lang_en)
            $completions[ $root_cmd + ' completion ' + $_ + ' language en-US'] = @('en-US', $tip, $_i)
        }
        $_i++
    }

    $PSCompletions.comp_config.PSObject.Properties.Name | ForEach-Object {
        if ($PSCompletions.comp_config.$_) {
            $core_info = (Get-Content -Raw ($PSCompletions.path.completions + '\' + $_ + '\lang\' + $PSCompletions.lang + '.json') | ConvertFrom-Json).$($_ + '_core_info')

            $configs = $core_info.comp_config.PSObject.Properties.Name
            foreach ($config in $configs) {
                $tip = $PSCompletions.fn_replace($core_info.comp_config.$config) -replace '<\$\w+>', ''
                $completions[ $root_cmd + ' completion ' + $_ + ' ' + $config] = @($config, $tip , $_i)
                $value = $PSCompletions.comp_config.$_.$config
                $completions[ $root_cmd + ' completion ' + $_ + ' ' + $config + ' ' + $value ] = @($value, ($PSCompletions.json.default_value + $value) , $_i)
                $_i++
            }
        }
    }

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

    @(
        'item', 'item_back',
        'selected', 'selected_back',
        'filter', 'filter_back',
        'border', 'border_back',
        'status', 'status_back',
        'tip', 'tip_back'
    ) | ForEach-Object {
        foreach ($item in $available_color) {
            $completions[$root_cmd + ' ui custom color ' + $_ + ' ' + $item] = @($item, ($item + "`n"), $_i)
            $_i++
        }
    }

    if ($PSCompletions.update) {
        $PSCompletions.update | ForEach-Object {
            $tip = $PSCompletions.fn_replace($PSCompletions.json.update)
            $completions[ $root_cmd + ' update ' + $_] = @($_, $tip, $_i)
            $_i++
        }
    }

    $PSCompletions.comp_cmd.keys | ForEach-Object {
        $alias = $PSCompletions.comp_cmd.$_
        $tip_rm = $PSCompletions.fn_replace($PSCompletions.json.remove)
        if ($_ -ne 'PSCompletions') {
            $completions[$root_cmd + ' rm ' + $_] = @($_, $tip_rm, $_i)
        }

        $tip_order = $PSCompletions.fn_replace($PSCompletions.json.order)
        $completions[$root_cmd + ' order reset ' + $_] = @($_, $tip_order, $_i)

        $tip_which = $PSCompletions.fn_replace($PSCompletions.json.which)
        $completions[$root_cmd + ' which ' + $_] = @($_, $tip_which, $_i)

        $tip_alias_add = $PSCompletions.fn_replace($PSCompletions.json.alias_add)
        $completions[$root_cmd + ' alias add ' + $_] = @($_, $tip_alias_add, $_i)

        $default = $_ -eq $alias
        $default_psc = $_ -eq 'PSCompletions' -and $alias -eq 'psc'
        if (!($default -or $default_psc)) {
            $tip_alias_rm = $PSCompletions.fn_replace($PSCompletions.json.alias_rm)
            $completions[$root_cmd + ' alias rm ' + $alias] = @($alias, $tip_alias_rm, $_i)
        }
        $_i++
    }
    #endregion

    #region : Running
    $input_arr = $command_ast.CommandElements
    $space_tab = if (!$word_to_complete.length) { 1 }else { 0 }
    $match = if ($space_tab) { ' *' }else { '*' }

    $filter_list = $completions.Keys | Where-Object {
        $cmd = $_ -split ' '
        $cmd.Count -eq ($input_arr.Count + $space_tab) -and ($cmd -join ' ') -like (($input_arr -join ' ') + $match)
    } | Sort-Object { $completions.$_[-1] }

    function complete_by_old {
        $max_len = 0
        $display_count = 0
        $cmd_line = [System.Console]::WindowHeight - 5

        $filter_list | ForEach-Object {
            $len = $completions[$_][0].Length
            if ($len -ge $max_len) { $max_len = $len }
        }
        $comp_count = $cmd_line * ([math]::Floor([System.Console]::WindowWidth) / ($max_len + 2))

        $filter_list | ForEach-Object {
            if ($comp_count -gt $display_count) {
                $display_count++
                $item = $completions[$_][0]
                [CompletionResult]::new($item, $item, 'ParameterValue', ($PSCompletions.fn_replace($completions[$_][1])))
            }
            else {
                [CompletionResult]::new(' ', '...', 'ParameterValue', $PSCompletions.json.comp_hide)
                return
            }
        }
        if ($display_count -eq 1) { ' ' }
    }
    if ($PSCompletions.ui.show -and $PSVersionTable.Platform -ne 'Unix') {
        $PSCompletions.ui.show()
    }
    else { complete_by_old }

    $PSCompletions.fn_order_job($PSScriptRoot, $root_cmd)
    #endregion
}
