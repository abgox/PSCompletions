function handleCompletions($completions) {
    $tempList = @()

    $branch_list = git branch --format='%(refname:lstrip=2)' 2>$null
    $head_list = @{
        HEAD       = (git show HEAD --relative-date -q 2>$null) -join "`n"
        FETCH_HEAD = (git show FETCH_HEAD --relative-date -q 2>$null) -join "`n"
        ORIG_HEAD  = (git show ORIG_HEAD --relative-date -q 2>$null) -join "`n"
        MERGE_HEAD = (git show MERGE_HEAD --relative-date -q 2>$null) -join "`n"
    }
    foreach ($_ in @('HEAD', 'FETCH_HEAD', 'ORIG_HEAD', 'MERGE_HEAD')) {
        if (!$head_list.$_) {
            $head_list.Remove($_)
        }
    }
    $branch_head_list = $branch_list + $head_list.Keys
    $remote_list = git remote 2>$null
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
    $tag_list = git tag 2>$null

    foreach ($_ in $branch_list) {
        $info = 'branch --- ' + $_
        $tempList += $PSCompletions.return_completion("switch $($_)", $info)
        $tempList += $PSCompletions.return_completion("branch $($_)", $info)
        $tempList += $PSCompletions.return_completion("merge $($_)", $info)
        $tempList += $PSCompletions.return_completion("diff $($_)", $info)
    }
    foreach ($_ in $head_list.Keys) {
        $info = $head_list.$_
        $tempList += $PSCompletions.return_completion("rebase -i $($_)", $info)
        $tempList += $PSCompletions.return_completion("rebase --interactive $($_)", $info)
        $tempList += $PSCompletions.return_completion("diff $($_)", $info)
        $tempList += $PSCompletions.return_completion("reset $($_)", $info)
        $tempList += $PSCompletions.return_completion("reset --soft $($_)", $info)
        $tempList += $PSCompletions.return_completion("reset --hard $($_)", $info)
        $tempList += $PSCompletions.return_completion("reset --mixed $($_)", $info)
        $tempList += $PSCompletions.return_completion("show $($_)", $info)
    }
    foreach ($_ in $branch_head_list) {
        $info = if ($head_list.$_) { $head_list.$_ }else { 'branch --- ' + $_ }
        $tempList += $PSCompletions.return_completion("checkout $($_)", $info)
    }
    foreach ($_ in $remote_list) {
        $info = 'remote --- ' + $_
        $tempList += $PSCompletions.return_completion("push $($_)", $info)
        $tempList += $PSCompletions.return_completion("pull $($_)", $info)
        $tempList += $PSCompletions.return_completion("fetch $($_)", $info)
        $tempList += $PSCompletions.return_completion("remote rename $($_)", $info)
        $tempList += $PSCompletions.return_completion("remote rm $($_)", $info)
    }
    foreach ($_ in $commit_info) {
        $hash = $_[0]
        $date = $_[1]
        $author = $_[2]
        $commit = $_[3..($_.Length - 1)]
        $content = $date + "`n" + $author + "`n" + ($commit -join "`n")

        $tempList += $PSCompletions.return_completion("commit -C $($hash)", $content)
        $tempList += $PSCompletions.return_completion("rebase -i $($hash)", $content)
        $tempList += $PSCompletions.return_completion("rebase --interactive $($hash)", $content)
        $tempList += $PSCompletions.return_completion("checkout $($hash)", $content)
        $tempList += $PSCompletions.return_completion("diff $($hash)", $content)
        $tempList += $PSCompletions.return_completion("reset $($hash)", $content)
        $tempList += $PSCompletions.return_completion("reset --soft $($hash)", $content)
        $tempList += $PSCompletions.return_completion("reset --hard $($hash)", $content)
        $tempList += $PSCompletions.return_completion("reset --mixed $($hash)", $content)
        $tempList += $PSCompletions.return_completion("show $($hash)", $content)
        $tempList += $PSCompletions.return_completion("revert $($hash)", $content)
        $tempList += $PSCompletions.return_completion("commit $($hash)", $content)
    }
    foreach ($_ in $tag_list) {
        $tempList += $PSCompletions.return_completion("tag -d $($_)", "tag --- $($_)")
        $tempList += $PSCompletions.return_completion("tag -v $($_)", "tag --- $($_)")
    }
    foreach ($_ in git stash list --encoding=gbk 2>$null) {
        if ($_ -match 'stash@\{(\d+)\}') {
            $stashId = $matches[1]
            $tempList += $PSCompletions.return_completion("stash show $stashId", $_)
            $tempList += $PSCompletions.return_completion("stash pop $stashId", $_)
            $tempList += $PSCompletions.return_completion("stash apply $stashId", $_)
            $tempList += $PSCompletions.return_completion("stash drop $stashId", $_)
        }
    }
    return $tempList + $completions
}
