# Refer to: https://pscompletions.abgox.com/docs/completion/hooks
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
    function add_toolchains {
        rustup toolchain list -q 2>$null | ForEach-Object { add $_ }
    }
    function add_targets {
        rustup target list --installed -q 2>$null | ForEach-Object { add $_ }
    }
    function add_components {
        rustup component list --installed -q 2>$null | ForEach-Object { add $_ }
    }
    function add_components_all {
        rustup component list -q 2>$null | ForEach-Object { add $_ }
    }
    function add_targets_all {
        rustup target list -q 2>$null | ForEach-Object { add $_ }
    }

    switch ($cmds[0].text) {
        'default' {
            add_toolchains
        }
        'uninstall' {
            add_toolchains
        }
        'override' {
            if ($cmds[1].text -eq 'set') {
                add_toolchains
            }
        }
        'run' {
            add_toolchains
        }
        'toolchain' {
            if ($cmds[1].text -in 'install', 'uninstall') {
                add_toolchains
            }
        }
        'target' {
            switch ($cmds[1].text) {
                'add' { add_targets_all }
                'remove' { add_targets }
            }
        }
        'component' {
            switch ($cmds[1].text) {
                'add' { add_components_all }
                'remove' { add_components }
            }
        }
    }

    return $list + $completions
}
