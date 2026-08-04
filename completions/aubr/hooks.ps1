function handleCompletions($completions) {
    if ($PSCompletions.pending.text -like '-*') {
        return $completions
    }
    if (-not (Test-Path 'package.json')) {
        return $completions
    }
    $list = [System.Collections.Generic.List[object]]::new()
    $tokens = @($PSCompletions.tokens)
    $unknown = @($tokens | Where-Object type -EQ 'unknown')
    $unknown_text = @($unknown.text)
    function add {
        param([string]$completion, [array]$tip = $completion, [array]$symbol = @(), [switch]$noSkip)
        if ((-not $completion -or -not $noSkip) -and ($completion -in $unknown_text -or ($PSCompletions.pending -and $completion -notlike "$($PSCompletions.pending.text)*"))) { return }
        $list.Add($PSCompletions.return_completion($completion, $tip, $symbol))
    }

    $packageJson = $PSCompletions.ConvertFrom_JsonAsHashtable($PSCompletions.get_raw_content('package.json'))
    $scripts = $packageJson.scripts

    function add_scripts {
        if (-not $scripts) {
            return
        }
        foreach ($item in $scripts.Keys) {
            add $item $scripts.$item
        }
    }

    if ($unknown.Count -eq 0) {
        add_scripts
    }

    return $list + $completions
}
