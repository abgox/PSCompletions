function handleCompletions($completions) {
    if ($PSCompletions.pending.text -like '-*') {
        return $completions
    }
    $list = [System.Collections.Generic.List[object]]::new()
    $tokens = @($PSCompletions.tokens)
    # $tokens_text = @($tokens.text)
    $cmds = @($tokens | Where-Object type -EQ 'command')
    # $cmds_text = @($cmds.text)
    # $opts = @($tokens | Where-Object type -EQ 'option')
    # $opts_text = @($opts.text)
    $unknown = @($tokens | Where-Object type -EQ 'unknown')
    $unknown_text = @($unknown.text)
    function add {
        param([string]$completion, [array]$tip = $completion, [array]$symbol = @(), [switch]$noSkip)
        if ((-not $completion -or -not $noSkip) -and ($completion -in $unknown_text -or ($PSCompletions.pending -and $completion -notlike "$($PSCompletions.pending.text)*"))) { return }
        $list.Add($PSCompletions.return_completion($completion, $tip, $symbol))
    }
    function add_completions {
        $rest = $PSCompletions.data.list | Where-Object { $_ -notin $unknown_text }
        $symbol = if ($rest.Count -gt 1) { @('SpaceTab') }else { , @() }
        foreach ($completion in $rest) { add $completion (get_completion_info $completion) $symbol }
    }
    function get_completion_info {
        param ([string]$completion)
        @"
{{
`$c = Get-Content -Raw "$($PSCompletions.path.completions_json)" -Encoding utf8 -ErrorAction SilentlyContinue | ConvertFrom-Json | Select-Object -ExpandProperty meta | Select-Object -ExpandProperty "$completion";
`$m = `$c.'$($PSCompletions.config.language)';
if (!`$m) { `$m = `$c.'en-US' }
if (`$m) {
    if (`$m.url) { 'url: ' + `$m.url; "`n"}
    if (`$m.description) { '-----'; "`n"; `$m.description -join "`n"}
}
}}
"@
    }

    if ($PSCompletions.config.enable_cache) {
        $PSCompletions.info = $PSCompletions.completions.psc.info
    }

    switch ($cmds[0].text) {
        'add' {
            $rest = $PSCompletions.list | Where-Object { $_ -notin $unknown_text -and $_ -notin $PSCompletions.data.list }
            $symbol = if ($rest.Count -gt 1) { @('SpaceTab') }else { , @() }
            foreach ($completion in $rest) {
                add $completion (get_completion_info $completion) $symbol
            }
        }
        { $_ -in 'rm', 'update', 'info', 'which' } { add_completions }
        'alias' {
            switch ($cmds[1].text) {
                'add' {
                    if ($unknown.Count) {
                        break
                    }
                    foreach ($completion in $PSCompletions.data.list) {
                        add $completion $PSCompletions.replace_content($PSCompletions.info.alias.add.tip)
                    }
                }
                'rm' {
                    if ($unknown.Count) {
                        $cmd = $unknown[0].text
                        $alias = for ($i = 0; $i -lt $unknown.Count; $i++) { if ($i) { $unknown[$i].text } }
                        $rest = $PSCompletions.data.alias.$cmd | Where-Object { $_ -notin $alias }
                        if ($rest.Count -gt 2) {
                            $symbol = @('SpaceTab')
                        }
                        foreach ($completion in $rest) {
                            add -noSkip $completion $PSCompletions.replace_content($PSCompletions.info.alias.rm.tip_v) $symbol
                        }
                        break
                    }
                    add_completions
                }
            }
        }
        'completion' {
            if ($unknown.Count -ge 3) {
                break
            }
            if ($unknown.Count -eq 0) {
                add_completions
                break
            }
            $completion = $unknown[0].text
            if ($completion -notin $PSCompletions.list) {
                break
            }
            $language = $PSCompletions.get_language($completion)
            $json = $PSCompletions.get_raw_content("$($PSCompletions.path.completions)/$($completion)/language/$($language).json") | ConvertFrom-Json
            if ($unknown.Count -eq 1) {
                add 'language' $PSCompletions.replace_content($PSCompletions.info.completion.language.tip) @('SpaceTab')
                add 'enable_tip' $PSCompletions.replace_content($PSCompletions.info.completion.enable_tip.tip) @('SpaceTab')
                if ($PSCompletions.config.comp_config[$completion].Count) {
                    if ($PSCompletions.config.comp_config[$completion].keys.Contains('enable_hooks')) {
                        $tip = $PSCompletions.replace_content($PSCompletions.info.completion.enable_hooks.tip) -replace '<@\w+>', ''
                        add 'enable_hooks' $tip @('SpaceTab')
                        add 'enable_hooks_tip' $PSCompletions.replace_content($PSCompletions.info.completion.enable_hooks_tip.tip) @('SpaceTab')
                    }
                }
                foreach ($c in $json.config) {
                    $config_item = $c.name
                    $tip = $PSCompletions.replace_content($c.tip -join "`n") -replace '<\@\w+>', ''
                    $symbol = if ($c.values) { @('SpaceTab') }else { , @() }
                    add $c.name $tip $symbol
                }
                break
            }
            switch ($unknown[1].text) {
                'language' {
                    $config = $PSCompletions.get_raw_content("$($PSCompletions.path.completions)/$($completion)/config.json") | ConvertFrom-Json
                    foreach ($language in $config.language) {
                        add $language $PSCompletions.replace_content($PSCompletions.info.completion.language.tip_v)
                    }
                }
                { $_ -like 'enable_*' } {
                    foreach ($value in 0..1) {
                        add $value $PSCompletions.replace_content($PSCompletions.info.set_value)
                    }
                }
                default {
                    $c = $json.config.Where({ $_.name -eq $tokens[2].text })
                    foreach ($value in $c.values) {
                        add $value $PSCompletions.replace_content($PSCompletions.info.set_value)
                    }
                }
            }
        }
        'menu' {
            if ($cmds[1].text -eq 'custom' -and $cmds[2].text -eq 'color' -and $cmds[3].text -in $PSCompletions.menu.const.color_item) {
                foreach ($color in $PSCompletions.menu.const.color_value) {
                    add $color $PSCompletions.replace_content($PSCompletions.info.menu.custom.color.tip)
                }
            }
        }
        'reset' {
            switch ($cmds[1].text) {
                'alias' {
                    add_completions
                }
                'completion' {
                    add_completions
                }
            }
        }
    }

    return $completions + $list
}
