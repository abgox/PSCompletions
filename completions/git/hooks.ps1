function handleCompletions($completions) {
    if ($PSCompletions.pending.text -like '-*') {
        return $completions
    }
    $list = [System.Collections.Generic.List[object]]::new()
    $tokens = @($PSCompletions.tokens)
    # $tokens_text = @($tokens.text)
    $cmds = @($tokens | Where-Object type -EQ 'command')
    # $cmds_text = @($cmds.text)
    $opts = @($tokens | Where-Object type -EQ 'option')
    # $opts_text = @($opts.text)
    $unknown = @($tokens | Where-Object type -EQ 'unknown')
    $unknown_text = @($unknown.text)
    function add {
        param([string]$completion, [array]$tip = $completion, [array]$symbol = @(), [switch]$noSkip)
        if ((-not $completion -or -not $noSkip) -and ($completion -in $unknown_text -or ($PSCompletions.pending -and $completion -notlike "$($PSCompletions.pending.text)*"))) { return }
        $list.Add($PSCompletions.return_completion($completion, $tip, $symbol))
    }
    function add_branch {
        git branch --format='%(refname:lstrip=2)' 2>$null | ForEach-Object {
            if ($_ -notlike '(HEAD detached from*') {
                add $_ "branch --- $_"
            }
        }
    }
    function add_head {
        'HEAD', 'FETCH_HEAD', 'ORIG_HEAD', 'MERGE_HEAD' | ForEach-Object {
            add $_ ((git show $_ --relative-date -q 2>$null) -join "`n")
        }
    }
    function add_commit {
        if ($PSCompletions.config.completion.git.max_commit -in '', $null) {
            $PSCompletions.config.completion.git.max_commit = 30
        }
        $guid = [guid]::NewGuid().Guid
        $git_info = git log --pretty="format:%h%nDate: %cr%nAuthor: %an <%ae>%n%B%n$($guid)" -n $PSCompletions.config.completion.git.max_commit 2>$null
        $current_commit = @()
        foreach ($_ in $git_info) {
            if ($_ -ne $guid) {
                $current_commit += $_
            }
            else {
                $hash = $current_commit[0]
                $date = $current_commit[1]
                $author = $current_commit[2]
                $commit = $current_commit[3..($current_commit.Length - 1)]
                $content = $date + "`n" + $author + "`n" + ($commit -join "`n")
                add $hash $content
                $current_commit = @()
            }
        }
    }
    function add_stash {
        git stash list 2>$null | ForEach-Object {
            if ($_ -match 'stash@\{(\d+)\}') {
                $stashId = $matches[1]
                add $matches[1] $_
            }
        }
    }
    function add_remote {
        git remote 2>$null | ForEach-Object { add $_ "remote --- $_" }
    }
    function add_tag {
        git tag -l 2>$null | ForEach-Object { add $_ "remote --- $_" }
    }

    switch ($cmds[0].text) {
        'add' {
            git status --porcelain 2>$null |
            Where-Object { $_ -match '^.[MD] ' -or $_ -match '^\?\? ' } |
            ForEach-Object { add $_.Substring(3) $_ }
        }
        'checkout' {
            if ($unknown.Count -eq 0) {
                add_branch
                add_head
                add_commit
            }
        }
        'switch' {
            if ($unknown.Count -eq 0) {
                add_branch
            }
        }
        'stash' {
            if ($unknown.Count -eq 0 -and $cmds[1].text -in 'show', 'pop', 'apply', 'drop') {
                add_stash
            }
        }
        'branch' {
            if ($opts[-1].text -in '-m', '-d') {
                add_branch
            }
        }
        'commit' {
            if ($unknown.Count -eq 0 -and $opts[-1].text -in '-C', '--squash') {
                add_commit
            }
        }
        'merge' {
            if ($unknown.Count -eq 0) {
                add_branch
            }
        }
        'diff' {
            add_commit
        }
        'rebase' {
            add_branch
            add_head
            add_commit
        }
        'reset' {
            if ($unknown.Count -eq 0) {
                add_head
                add_commit
            }
        }
        'show' {
            if ($unknown.Count -eq 0) {
                add_head
                add_commit
            }
        }
        { $_ -in 'push', 'pull', 'fetch' } {
            if ($unknown.Count -eq 0) {
                add_remote
            }
        }
        'remote' {
            if ($cmds[1].text -in 'rename', 'rm') {
                add_remote
            }
        }
        'revert' {
            if ($unknown.Count -eq 0) {
                add_commit
            }
        }
        'tag' {
            if ($opts[-1].text -in '-d', '-v') {
                add_tag
            }
        }
    }

    return $list + $completions
}
