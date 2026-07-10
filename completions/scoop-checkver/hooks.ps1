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

    $manifests = Get-ChildItem bucket -Recurse -File -Filter *.json -ErrorAction Ignore
    foreach ($m in $manifests) {
        add $m.BaseName $m.FullName
    }

    return $list + $completions
}
