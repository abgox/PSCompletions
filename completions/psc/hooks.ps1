function handleCompletions($completions) {
    $list = @()

    $filter_input_arr = $PSCompletions.filter_input_arr
    if ($PSCompletions.config.enable_cache) {
        $PSCompletions.info = $PSCompletions.completions.psc.info
    }

    switch ($filter_input_arr[0]) {
        'add' {
            if ('*' -in $filter_input_arr) {
                break
            }
            $symbol = @()
            if ($filter_input_arr.Count -le 1) {
                $add = @()
                $rest = $PSCompletions.list.Where({ $_ -notin $PSCompletions.data.list })
            }
            else {
                $add = $filter_input_arr[1..($filter_input_arr.Count - 1)]
                $rest = $PSCompletions.list.Where({ $_ -notin $PSCompletions.data.list -and $_ -notin $add })
            }
            if ($rest.Count -gt 1) {
                $symbol = @('SpaceTab')
            }
            foreach ($completion in $rest) {
                $list += $PSCompletions.return_completion($completion, $PSCompletions.replace_content($PSCompletions.info.add.tip), $symbol)
            }
        }
        'rm' {
            if ('*' -in $filter_input_arr) {
                break
            }
            $symbol = @()
            if ($filter_input_arr.Count -le 1) {
                $rm = @()
                $rest = $PSCompletions.data.list
            }
            else {
                $rm = $filter_input_arr[1..($filter_input_arr.Count - 1)]
                $rest = $PSCompletions.data.list.Where({ $_ -notin $rm })
            }
            if ($rest.Count -gt 1) {
                $symbol = @('SpaceTab')
            }
            foreach ($completion in $rest) {
                $list += $PSCompletions.return_completion($completion, $PSCompletions.replace_content($PSCompletions.info.rm.tip), $symbol)
            }
        }
        'update' {
            if ('*' -in $filter_input_arr) {
                break
            }
            $symbol = @()
            if ($filter_input_arr.Count -le 1) {
                $update = @()
                $rest = $PSCompletions.update
            }
            else {
                $update = $filter_input_arr[1..($filter_input_arr.Count - 1)]
                $rest = $PSCompletions.update.Where({ $_ -notin $update })
            }
            if ($rest.Count -gt 1) {
                $symbol = @('SpaceTab')
            }
            foreach ($completion in $rest) {
                $list += $PSCompletions.return_completion($completion, $PSCompletions.replace_content($PSCompletions.info.update.tip), $symbol)
            }
        }
        'which' {
            if ('*' -in $filter_input_arr) {
                break
            }
            $symbol = @()
            if ($filter_input_arr.Count -le 1) {
                $which = @()
                $rest = $PSCompletions.data.list
            }
            else {
                $which = $filter_input_arr[1..($filter_input_arr.Count - 1)]
                $rest = $PSCompletions.data.list.Where({ $_ -notin $which })
            }
            if ($rest.Count -gt 1) {
                $symbol = @('SpaceTab')
            }
            foreach ($completion in $rest) {
                $list += $PSCompletions.return_completion($completion, $PSCompletions.replace_content($PSCompletions.info.which.tip), $symbol)
            }
        }
        'alias' {
            switch ($filter_input_arr[1]) {
                'add' {
                    if ($filter_input_arr.Count -eq 2) {
                        foreach ($completion in $PSCompletions.data.list) {
                            $list += $PSCompletions.return_completion($completion, $PSCompletions.replace_content($PSCompletions.info.alias.add.tip))
                        }
                    }
                }
                'rm' {
                    if ($filter_input_arr.Count -le 2) {
                        foreach ($completion in $PSCompletions.data.list) {
                            $symbol = @()
                            if ($PSCompletions.data.alias.$completion.Count -gt 1) {
                                $symbol = @('SpaceTab')
                            }
                            $list += $PSCompletions.return_completion($completion, $PSCompletions.replace_content($PSCompletions.info.alias.rm.tip), $symbol)
                        }
                    }
                    else {
                        $cmd = $filter_input_arr[2]
                        if ($filter_input_arr.Count -le 3) {
                            $alias = @()
                            $rest = $PSCompletions.data.alias.$cmd
                        }
                        else {
                            $alias = $filter_input_arr[3..($filter_input_arr.Count - 1)]
                            $rest = $PSCompletions.data.alias.$cmd.Where({ $_ -notin $alias })
                        }
                        if ($rest.Count -gt 1) {
                            if ($rest.Count -gt 2) {
                                $symbol = @('SpaceTab')
                            }
                            else {
                                $symbol = @()
                            }
                            foreach ($completion in $rest) {
                                $list += $PSCompletions.return_completion($completion, $PSCompletions.replace_content($PSCompletions.info.alias.rm.tip_v), $symbol)
                            }
                        }
                    }
                }
            }
        }
        'completion' {
            if ($filter_input_arr.Count -le 1) {
                foreach ($completion in $PSCompletions.data.list) {
                    $list += $PSCompletions.return_completion($completion, $PSCompletions.replace_content($PSCompletions.info.completion.tip), @('SpaceTab'))
                }
            }
            else {
                $completion = $filter_input_arr[1]

                $language = $PSCompletions.get_language($completion)
                $json = $PSCompletions.get_raw_content("$($PSCompletions.path.completions)/$($completion)/language/$($language).json") | ConvertFrom-Json

                switch ($filter_input_arr.Count) {
                    2 {
                        $list += $PSCompletions.return_completion("language", $PSCompletions.replace_content($PSCompletions.info.completion.language.tip), @('SpaceTab'))
                        $list += $PSCompletions.return_completion("enable_tip", $PSCompletions.replace_content($PSCompletions.info.completion.enable_tip.tip), @('SpaceTab'))

                        if ($PSCompletions.config.comp_config[$completion].Count) {
                            if ($PSCompletions.config.comp_config[$completion].keys.Contains('enable_hooks')) {
                                $tip = $PSCompletions.replace_content($PSCompletions.info.completion.enable_hooks.tip) -replace '<@\w+>', ''
                                $list += $PSCompletions.return_completion('enable_hooks', $tip, @('SpaceTab'))

                                $list += $PSCompletions.return_completion("enable_hooks_tip", $PSCompletions.replace_content($PSCompletions.info.completion.enable_hooks_tip.tip), @('SpaceTab'))
                            }
                        }
                        foreach ($c in $json.config) {
                            $config_item = $c.name
                            $tip = $PSCompletions.replace_content($c.tip -join "`n") -replace '<\@\w+>', ''
                            $symbol = @()
                            if ($c.values) {
                                $symbol = @('SpaceTab')
                            }
                            if ($filter_input_arr.Count -eq 2) {
                                $list += $PSCompletions.return_completion($c.name, $tip, $symbol)
                            }
                        }
                    }
                    3 {
                        switch ($filter_input_arr[2]) {
                            'language' {
                                $config = $PSCompletions.get_raw_content("$($PSCompletions.path.completions)/$($completion)/config.json") | ConvertFrom-Json
                                foreach ($language in $config.language) {
                                    $list += $PSCompletions.return_completion($language, $PSCompletions.replace_content($PSCompletions.info.completion.language.tip_v))
                                }
                            }
                            { $_ -in 'enable_tip', 'enable_hooks', 'enable_hooks_tip' } {
                                foreach ($value in 0..1) {
                                    $list += $PSCompletions.return_completion($value, $PSCompletions.replace_content($PSCompletions.info.set_value))
                                }
                            }
                            Default {
                                $c = $json.config.Where({ $_.name -eq $filter_input_arr[2] })
                                foreach ($value in $c.values) {
                                    $list += $PSCompletions.return_completion($value, $PSCompletions.replace_content($PSCompletions.info.set_value))
                                }
                            }
                        }
                    }
                }
            }
        }
        'menu' {
            if ($filter_input_arr.Count -eq 4 -and $filter_input_arr[1] -eq 'custom' -and $filter_input_arr[2] -eq 'color' -and $filter_input_arr[3] -in $PSCompletions.menu.const.color_item) {
                foreach ($color in $PSCompletions.menu.const.color_value) {
                    $list += $PSCompletions.return_completion($color, $PSCompletions.replace_content($PSCompletions.info.menu.custom.color.tip))
                }
            }
        }
        'reset' {
            if ('*' -in $filter_input_arr) {
                break
            }
            switch ($filter_input_arr[1]) {
                'alias' {
                    $symbol = @()
                    if ($filter_input_arr.Count -le 1) {
                        $reset = @()
                        $rest = $PSCompletions.data.list
                    }
                    else {
                        $reset = $filter_input_arr[1..($filter_input_arr.Count - 1)]
                        $rest = $PSCompletions.data.list.Where({ $_ -notin $reset })
                    }
                    if ($rest.Count -gt 1) {
                        $symbol = @('SpaceTab')
                    }
                    foreach ($completion in $rest) {
                        $list += $PSCompletions.return_completion($completion, $PSCompletions.replace_content($PSCompletions.info.reset.alias.tip), $symbol)
                    }
                }
                'completion' {
                    if ($filter_input_arr.Count -eq 2) {
                        foreach ($completion in $PSCompletions.data.list) {
                            if ($PSCompletions.data.config.comp_config[$completion].Keys) {
                                $symbol = @('SpaceTab')
                            }
                            else {
                                $symbol = @()
                            }
                            $list += $PSCompletions.return_completion($completion, $PSCompletions.replace_content($PSCompletions.info.reset.completion.tip), $symbol )
                        }
                    }
                    if ($filter_input_arr.Count -ge 3) {
                        $selected = $filter_input_arr[3, ($filter_input_arr.Count - 1)]
                        $completion = $filter_input_arr[2]
                        $add = @()
                        if ($PSCompletions.data.config.comp_config[$completion].Keys) {
                            foreach ($config_item in $PSCompletions.data.config.comp_config.$completion.Keys) {
                                if ($config_item -notin $selected) {
                                    $add += $config_item
                                }
                            }
                            $symbol = if ($add.Count -gt 1) { @('SpaceTab') }else { , @() }
                            foreach ($config_item in $add) {
                                $list += $PSCompletions.return_completion($config_item, $PSCompletions.replace_content($PSCompletions.info.reset.completion.tip_v), $symbol)
                            }
                        }
                    }
                }
            }
        }
        Default {
            return $completions
        }
    }
    return $completions + $list
}
