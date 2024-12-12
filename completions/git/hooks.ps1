function handleCompletions($completions) {
    $tempList = @()

    function return_branch {
        return git branch --format='%(refname:lstrip=2)' 2>$null
    }

    function return_head {
        $head_list = @{
            HEAD       = (git show HEAD --relative-date -q --encoding=gbk 2>$null) -join "`n"
            FETCH_HEAD = (git show FETCH_HEAD --relative-date -q --encoding=gbk 2>$null) -join "`n"
            ORIG_HEAD  = (git show ORIG_HEAD --relative-date -q --encoding=gbk 2>$null) -join "`n"
            MERGE_HEAD = (git show MERGE_HEAD --relative-date -q --encoding=gbk 2>$null) -join "`n"
        }
        foreach ($_ in @('HEAD', 'FETCH_HEAD', 'ORIG_HEAD', 'MERGE_HEAD')) {
            if (!$head_list[$_]) {
                $head_list.Remove($_)
            }
        }
        return $head_list
    }
    function return_commit {
        $commit_info = [System.Collections.Generic.List[array]]::new()
        if ($PSCompletions.config.comp_config.git.max_commit -in @('', $null)) {
            $PSCompletions.config.comp_config.git.max_commit = 20
        }
        $guid = [guid]::NewGuid().Guid
        $git_info = git log --pretty="format:%h%nDate: %cr%nAuthor: %an <%ae>%n%B%n$($guid)" -n $PSCompletions.config.comp_config.git.max_commit --encoding=gbk 2>$null
        $current_commit = @()
        foreach ($_ in $git_info) {
            if ($_ -ne $guid) {
                $current_commit += $_
            }
            else {
                $commit_info.add($current_commit)
                $current_commit = @()
            }
        }
        $current_commit = $null
        return $commit_info
    }

    $last_item = $PSCompletions.filter_input_arr[-1]

    switch ($last_item) {
        'checkout' {
            $branch_list = return_branch
            $head_list = return_head
            $branch_head_list = $branch_list + $head_list.Keys

            foreach ($_ in $branch_head_list) {
                $info = if ($head_list[$_]) { $head_list[$_] }else { 'branch --- ' + $_ }
                $tempList += $PSCompletions.return_completion($_, $info)
            }
            $commit_info = return_commit
            foreach ($_ in $commit_info) {
                $hash = $_[0]
                $date = $_[1]
                $author = $_[2]
                $commit = $_[3..($_.Length - 1)]
                $content = $date + "`n" + $author + "`n" + ($commit -join "`n")

                $tempList += $PSCompletions.return_completion($hash, $content)
            }
        }
        'switch' {
            $branch_list = return_branch
            foreach ($_ in $branch_list) {
                $info = 'branch --- ' + $_
                $tempList += $PSCompletions.return_completion($_, $info)
            }
        }
        { 'stash' -in $PSCompletions.input_arr } {
            if ($last_item -in @('show', 'pop', 'apply', 'drop')) {
                foreach ($_ in git stash list --encoding=gbk 2>$null) {
                    if ($_ -match 'stash@\{(\d+)\}') {
                        $stashId = $matches[1]
                        $tempList += $PSCompletions.return_completion($stashId, $_)
                    }
                }
            }
        }
        { 'branch' -in $PSCompletions.input_arr } {
            if ($last_item -in @('-m', '-d')) {
                $branch_list = return_branch
                foreach ($_ in $branch_list) {
                    $info = 'branch --- ' + $_
                    $tempList += $PSCompletions.return_completion($_, $info)
                }
            }
        }
        { 'commit' -in $PSCompletions.input_arr } {
            if ($last_item -in @('-C')) {
                $commit_info = return_commit
                foreach ($_ in $commit_info) {
                    $hash = $_[0]
                    $date = $_[1]
                    $author = $_[2]
                    $commit = $_[3..($_.Length - 1)]
                    $content = $date + "`n" + $author + "`n" + ($commit -join "`n")

                    $tempList += $PSCompletions.return_completion($hash, $content)
                }
            }
        }
        'merge' {
            $branch_list = return_branch
            foreach ($_ in $branch_list) {
                $info = 'branch --- ' + $_
                $tempList += $PSCompletions.return_completion($_, $info)
            }
        }
        'diff' {
            $branch_list = return_branch
            foreach ($_ in $branch_list) {
                $info = 'branch --- ' + $_
                $tempList += $PSCompletions.return_completion($_, $info)
            }
            $head_list = return_head
            foreach ($_ in $head_list.Keys) {
                $info = $head_list.$_
                $tempList += $PSCompletions.return_completion($_, $info)
            }

            $commit_info = return_commit
            foreach ($_ in $commit_info) {
                $hash = $_[0]
                $date = $_[1]
                $author = $_[2]
                $commit = $_[3..($_.Length - 1)]
                $content = $date + "`n" + $author + "`n" + ($commit -join "`n")

                $tempList += $PSCompletions.return_completion($hash, $content)
            }
        }
        { 'rebase' -in $PSCompletions.input_arr } {
            if ($last_item -in @('-i', '--interactive')) {
                $head_list = return_head
                foreach ($_ in $head_list.Keys) {
                    $info = $head_list.$_
                    $tempList += $PSCompletions.return_completion($_, $info)
                }
                $commit_info = return_commit
                foreach ($_ in $commit_info) {
                    $hash = $_[0]
                    $date = $_[1]
                    $author = $_[2]
                    $commit = $_[3..($_.Length - 1)]
                    $content = $date + "`n" + $author + "`n" + ($commit -join "`n")

                    $tempList += $PSCompletions.return_completion($hash, $content)
                }
            }
        }
        'reset' {
            $head_list = return_head
            foreach ($_ in $head_list.Keys) {
                $info = $head_list.$_
                $tempList += $PSCompletions.return_completion($_, $info)
            }
            $commit_info = return_commit
            foreach ($_ in $commit_info) {
                $hash = $_[0]
                $date = $_[1]
                $author = $_[2]
                $commit = $_[3..($_.Length - 1)]
                $content = $date + "`n" + $author + "`n" + ($commit -join "`n")

                $tempList += $PSCompletions.return_completion($hash, $content)
            }
        }
        'show' {
            $head_list = return_head
            foreach ($_ in $head_list.Keys) {
                $info = $head_list.$_
                $tempList += $PSCompletions.return_completion($_, $info)
            }
            $commit_info = return_commit
            foreach ($_ in $commit_info) {
                $hash = $_[0]
                $date = $_[1]
                $author = $_[2]
                $commit = $_[3..($_.Length - 1)]
                $content = $date + "`n" + $author + "`n" + ($commit -join "`n")

                $tempList += $PSCompletions.return_completion($hash, $content)
            }
        }
        'push' {
            $remote_list = git remote 2>$null
            foreach ($_ in $remote_list) {
                $info = 'remote --- ' + $_
                $tempList += $PSCompletions.return_completion($_, $info)
            }
        }
        'pull' {
            $remote_list = git remote 2>$null
            foreach ($_ in $remote_list) {
                $info = 'remote --- ' + $_
                $tempList += $PSCompletions.return_completion($_, $info)
            }
        }
        'fetch' {
            $remote_list = git remote 2>$null
            foreach ($_ in $remote_list) {
                $info = 'remote --- ' + $_
                $tempList += $PSCompletions.return_completion($_, $info)
            }
        }
        { 'remote' -in $PSCompletions.input_arr } {
            if ($last_item -in @('rename', 'rm')) {
                $remote_list = git remote 2>$null
                foreach ($_ in $remote_list) {
                    $info = 'remote --- ' + $_
                    $tempList += $PSCompletions.return_completion($_, $info)
                }
            }
        }
        'revert' {
            $commit_info = return_commit
            foreach ($_ in $commit_info) {
                $hash = $_[0]
                $date = $_[1]
                $author = $_[2]
                $commit = $_[3..($_.Length - 1)]
                $content = $date + "`n" + $author + "`n" + ($commit -join "`n")

                $tempList += $PSCompletions.return_completion($hash, $content)
            }
        }
        { 'tag' -in $PSCompletions.input_arr } {
            if ($last_item -in @('-d', '-v')) {
                $tag_list = git tag 2>$null
                foreach ($_ in $tag_list) {
                    $tempList += $PSCompletions.return_completion($_, "tag --- $($_)")
                }
            }
        }
    }
    return $tempList + $completions
}
