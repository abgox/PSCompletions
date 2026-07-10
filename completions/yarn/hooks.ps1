function handleCompletions($completions) {
    if ($PSCompletions.pending.text -like '-*') {
        return $completions
    }
    if (-not (Test-Path 'package.json')) {
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

    $packageJson = $PSCompletions.ConvertFrom_JsonAsHashtable($PSCompletions.get_raw_content('package.json'))
    $scripts = $packageJson.scripts
    $dependencies = $packageJson.dependencies
    $devDependencies = $packageJson.devDependencies

    function add_scripts {
        if (-not $scripts) {
            return
        }
        foreach ($item in $scripts.Keys) {
            add $item $scripts.$item
        }
    }
    function add_dependencies {
        if (-not $dependencies) {
            return
        }
        foreach ($item in $dependencies.Keys) {
            add $item "dependency: $item ($($dependencies.$item))"
        }
    }
    function add_dependencies_dev {
        if (-not $devDependencies) {
            return
        }
        foreach ($item in $devDependencies.Keys) {
            add $item "devDependency: $item ($($devDependencies.$item))"
        }
    }

    switch ($cmds[0].text) {
        'run' {
            if ($unknown.Count -eq 0) {
                add_scripts
            }
        }
        'remove' {
            add_dependencies
            add_dependencies_dev
        }
        'upgrade' {
            add_dependencies
            add_dependencies_dev
        }
    }

    return $list + $completions
}
