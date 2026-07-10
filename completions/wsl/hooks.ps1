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

    function clean_nul {
        param($data)
        $res = [System.Collections.Generic.List[byte]]::new()
        foreach ($_ in [System.Text.Encoding]::UTF8.GetBytes($data)) {
            # Remove NUL(0x00) characters from binary data
            if ($_ -ne 0x00) { $res.add($_) }
        }
        return [System.Text.Encoding]::UTF8.GetString($res)
    }
    function add_distro {
        param([string]$typeTip)
        wsl -l -q 2>$null | ForEach-Object {
            $Distro = (clean_nul $_)
            add $Distro $PSCompletions.replace_content($PSCompletions.completions.wsl.info.tip.$typeTip)
        }
    }

    switch ($cmds[-1].text) {
        { $_ -in @('-d', '--distribution') } {
            add_distro '--distribution'
        }
        { $_ -in @('-s', '--set-default') } {
            add_distro '--set-default'
        }
        { $_ -in @('-t', '--terminate') } {
            add_distro '--terminate'
        }
        '--unregister' {
            add_distro '--unregister'
        }
        '--export' {
            add_distro '--export'
        }
    }

    return $list + $completions
}
