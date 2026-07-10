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

    function get_tools_dir {
        $voltaBinDir = Split-Path (Get-Command volta).Source -Parent
        $toolsDir = "$voltaBinDir\tools\image"
        if (!(Test-Path $toolsDir)) {
            $toolsDir = "$(Split-Path $voltaBinDir -Parent)\tools\image"
        }
        if (!(Test-Path $toolsDir)) {
            $toolsDir = "$env:LocalAppData\Volta\tools\image"
        }
        if (!(Test-Path $toolsDir)) {
            return
        }
        return $toolsDir
    }
    function add_version {
        $dir = get_tools_dir
        if ($dir -and (Test-Path $dir -PathType Container)) {
            Get-ChildItem $dir -Directory | ForEach-Object {
                $tool = $_.Name
                Get-ChildItem "$dir\$tool" -Directory | ForEach-Object { add "$tool@$($_.Name)" }
            }
        }
    }
    function add_package {
        $dir = get_tools_dir
        if ($dir -and (Test-Path $dir -PathType Container)) {
            Get-ChildItem "$dir\packages" -Directory | ForEach-Object { add $_.Name }
        }
    }

    switch ($cmds[0].text) {
        'pin' {
            add_version
        }
        'uninstall' {
            add_version
            add_package
        }
        'which' {
            Get-ChildItem (Split-Path (Get-Command volta).Source -Parent) -File -Filter '*.exe' | ForEach-Object {
                add $_.BaseName
            }
        }
    }

    return $list + $completions
}
