function handleCompletions($completions) {
    if ($completions -isnot [array]) {
        return $completions
    }
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
            if (!$head_list.$_) {
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

    if ('checkout' -in $PSCompletions.cmd) {
        $branch_list = return_branch
        $head_list = return_head
        $branch_head_list = $branch_list + $head_list.Keys

        foreach ($_ in $branch_head_list) {
            $info = if ($head_list.$_) { $head_list.$_ }else { 'branch --- ' + $_ }
            $tempList += $PSCompletions.return_completion("checkout $($_)", $info)
        }

        $commit_info = return_commit
        foreach ($_ in $commit_info) {
            $hash = $_[0]
            $date = $_[1]
            $author = $_[2]
            $commit = $_[3..($_.Length - 1)]
            $content = $date + "`n" + $author + "`n" + ($commit -join "`n")

            $tempList += $PSCompletions.return_completion("checkout $($hash)", $content)
        }
    }
    elseif ('stash' -in $PSCompletions.cmd) {
        foreach ($_ in git stash list --encoding=gbk 2>$null) {
            if ($_ -match 'stash@\{(\d+)\}') {
                $stashId = $matches[1]
                $tempList += $PSCompletions.return_completion("stash show $stashId", $_)
                $tempList += $PSCompletions.return_completion("stash pop $stashId", $_)
                $tempList += $PSCompletions.return_completion("stash apply $stashId", $_)
                $tempList += $PSCompletions.return_completion("stash drop $stashId", $_)
            }
        }
    }
    elseif ('switch' -in $PSCompletions.cmd) {
        $branch_list = return_branch
        foreach ($_ in $branch_list) {
            $info = 'branch --- ' + $_
            $tempList += $PSCompletions.return_completion("switch $($_)", $info)
        }
    }
    elseif ('branch' -in $PSCompletions.cmd) {
        $branch_list = return_branch
        foreach ($_ in $branch_list) {
            $info = 'branch --- ' + $_
            $tempList += $PSCompletions.return_completion("branch -m $($_)", $info)
            $tempList += $PSCompletions.return_completion("branch -d $($_)", $info)
        }
    }
    elseif ('commit' -in $PSCompletions.cmd) {
        $commit_info = return_commit
        foreach ($_ in $commit_info) {
            $hash = $_[0]
            $date = $_[1]
            $author = $_[2]
            $commit = $_[3..($_.Length - 1)]
            $content = $date + "`n" + $author + "`n" + ($commit -join "`n")

            $tempList += $PSCompletions.return_completion("commit -C $($hash)", $content)
        }
    }
    elseif ('merge' -in $PSCompletions.cmd) {
        $branch_list = return_branch
        foreach ($_ in $branch_list) {
            $info = 'branch --- ' + $_
            $tempList += $PSCompletions.return_completion("merge $($_)", $info)
        }
    }
    elseif ('diff' -in $PSCompletions.cmd) {
        $branch_list = return_branch
        foreach ($_ in $branch_list) {
            $info = 'branch --- ' + $_
            $tempList += $PSCompletions.return_completion("diff $($_)", $info)
        }
        $head_list = return_head
        foreach ($_ in $head_list.Keys) {
            $info = $head_list.$_
            $tempList += $PSCompletions.return_completion("diff $($_)", $info)
        }

        $commit_info = return_commit
        foreach ($_ in $commit_info) {
            $hash = $_[0]
            $date = $_[1]
            $author = $_[2]
            $commit = $_[3..($_.Length - 1)]
            $content = $date + "`n" + $author + "`n" + ($commit -join "`n")

            $tempList += $PSCompletions.return_completion("diff $($hash)", $content)
        }
    }
    elseif ('rebase' -in $PSCompletions.cmd) {
        $head_list = return_head
        foreach ($_ in $head_list.Keys) {
            $info = $head_list.$_
            $tempList += $PSCompletions.return_completion("rebase -i $($_)", $info)
            $tempList += $PSCompletions.return_completion("rebase --interactive $($_)", $info)
        }
        $commit_info = return_commit
        foreach ($_ in $commit_info) {
            $hash = $_[0]
            $date = $_[1]
            $author = $_[2]
            $commit = $_[3..($_.Length - 1)]
            $content = $date + "`n" + $author + "`n" + ($commit -join "`n")

            $tempList += $PSCompletions.return_completion("rebase -i $($hash)", $content)
            $tempList += $PSCompletions.return_completion("rebase --interactive $($hash)", $content)
        }
    }
    elseif ('reset' -in $PSCompletions.cmd) {
        $head_list = return_head
        foreach ($_ in $head_list.Keys) {
            $info = $head_list.$_
            $tempList += $PSCompletions.return_completion("reset $($_)", $info)
        }
        $commit_info = return_commit
        foreach ($_ in $commit_info) {
            $hash = $_[0]
            $date = $_[1]
            $author = $_[2]
            $commit = $_[3..($_.Length - 1)]
            $content = $date + "`n" + $author + "`n" + ($commit -join "`n")

            $tempList += $PSCompletions.return_completion("reset $($hash)", $content)
        }
    }
    elseif ('show' -in $PSCompletions.cmd) {
        $head_list = return_head
        foreach ($_ in $head_list.Keys) {
            $info = $head_list.$_
            $tempList += $PSCompletions.return_completion("show $($_)", $info)
        }
        $commit_info = return_commit
        foreach ($_ in $commit_info) {
            $hash = $_[0]
            $date = $_[1]
            $author = $_[2]
            $commit = $_[3..($_.Length - 1)]
            $content = $date + "`n" + $author + "`n" + ($commit -join "`n")

            $tempList += $PSCompletions.return_completion("show $($hash)", $content)
        }
    }
    elseif ('push' -in $PSCompletions.cmd) {
        $remote_list = git remote 2>$null
        foreach ($_ in $remote_list) {
            $info = 'remote --- ' + $_
            $tempList += $PSCompletions.return_completion("push $($_)", $info)
        }
    }
    elseif ('pull' -in $PSCompletions.cmd) {
        $remote_list = git remote 2>$null
        foreach ($_ in $remote_list) {
            $info = 'remote --- ' + $_
            $tempList += $PSCompletions.return_completion("pull $($_)", $info)
        }
    }
    elseif ('fetch' -in $PSCompletions.cmd) {
        $remote_list = git remote 2>$null
        foreach ($_ in $remote_list) {
            $info = 'remote --- ' + $_
            $tempList += $PSCompletions.return_completion("fetch $($_)", $info)
        }
    }
    elseif ('remote' -in $PSCompletions.cmd) {
        $remote_list = git remote 2>$null
        foreach ($_ in $remote_list) {
            $info = 'remote --- ' + $_
            $tempList += $PSCompletions.return_completion("remote rename $($_)", $info)
            $tempList += $PSCompletions.return_completion("remote rm $($_)", $info)
        }
    }
    elseif ('revert' -in $PSCompletions.cmd) {
        $commit_info = return_commit
        foreach ($_ in $commit_info) {
            $hash = $_[0]
            $date = $_[1]
            $author = $_[2]
            $commit = $_[3..($_.Length - 1)]
            $content = $date + "`n" + $author + "`n" + ($commit -join "`n")

            $tempList += $PSCompletions.return_completion("revert $($hash)", $content)
        }
    }
    elseif ('tag' -in $PSCompletions.cmd) {
        $tag_list = git tag 2>$null
        foreach ($_ in $tag_list) {
            $tempList += $PSCompletions.return_completion("tag -d $($_)", "tag --- $($_)")
            $tempList += $PSCompletions.return_completion("tag -v $($_)", "tag --- $($_)")
        }
    }
    return $tempList + $completions
}
