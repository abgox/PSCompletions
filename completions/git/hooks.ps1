function handleCompletions([System.Collections.Generic.List[System.Object]]$completions) {
    $tempList = [System.Collections.Generic.List[System.Object]]@()
    function addCompletion($name, $tip = ' ', $symbol = '') {
        $tempList.Add(@{
                name   = $name
                symbol = $symbol
                tip    = $tip
            })
    }
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
    $current_commit = [System.Collections.Generic.List[string]]::new()
    if ($PSCompletions.config.comp_config.git.max_commit -in @('', $null)) {
        $PSCompletions.config.comp_config.git.max_commit = 20
    }
    $git_info = git log --pretty='format:%h%nDate: %cr%nAuthor: %an <%ae>%n%B%n@@@--------------------@@@' -n $PSCompletions.config.comp_config.git.max_commit --encoding=gbk 2>$null
    foreach ($_ in $git_info) {
        if ($_ -ne '@@@--------------------@@@') {
            $current_commit.Add($_)
        }
        else {
            $commit_info.add($current_commit)
            $current_commit = [System.Collections.Generic.List[string]]::new()
        }
    }
    $current_commit = $null
    $tag_list = git tag 2>$null

    foreach ($_ in $branch_list) {
        $info = 'branch --- ' + $_

        addCompletion "switch $($_)" $info
        addCompletion "merge $($_)" $info
        addCompletion "diff $($_)" $info
    }
    foreach ($_ in $head_list.Keys) {
        $info = $head_list.$_
        addCompletion "rebase -i $($_)" $info
        addCompletion "rebase --interactive $($_)" $info
        addCompletion "diff $($_)" $info
        addCompletion "reset $($_)" $info
        addCompletion "reset --soft $($_)" $info
        addCompletion "reset --hard $($_)" $info
        addCompletion "reset --mixed $($_)" $info
        addCompletion "show $($_)" $info
    }
    foreach ($_ in $branch_head_list) {
        $info = if ($head_list.$_) { $head_list.$_ }else { 'branch --- ' + $_ }
        addCompletion "checkout $($_)" $info
    }
    foreach ($_ in $remote_list) {
        $info = 'remote --- ' + $_
        addCompletion "push $($_)" $info

        addCompletion "pull $($_)" $info
        addCompletion "fetch $($_)" $info
        addCompletion "remote rename $($_)" $info
        addCompletion "remote rm $($_)" $info
    }
    foreach ($_ in $commit_info) {
        $hash = $_[0]
        $date = $_[1]
        $author = $_[2]
        $commit = $_[3..($_.Length - 1)]
        $content = $date + "`n" + $author + "`n" + ($commit -join "`n")

        addCompletion "commit -C $($hash)" $content
        addCompletion "rebase -i $($hash)" $content
        addCompletion "rebase --interactive $($hash)" $content
        addCompletion "checkout $($hash)" $content
        addCompletion "diff $($hash)" $content
        addCompletion "reset $($hash)" $content
        addCompletion "reset --soft $($hash)" $content
        addCompletion "reset --hard $($hash)" $content
        addCompletion "reset --mixed $($hash)" $content
        addCompletion "show $($hash)" $content
        addCompletion "revert $($hash)" $content
        addCompletion "commit $($hash)" $content
    }
    foreach ($_ in $tag_list) {
        addCompletion "tag -d $($_)" "tag --- $($_)"
        addCompletion "tag -v $($_)" "tag --- $($_)"
    }
    foreach ($_ in git stash list --encoding=gbk 2>$null) {
        if ($_ -match 'stash@\{(\d+)\}') {
            $stashId = $matches[1]
            addCompletion "stash show $stashId" $_
            addCompletion "stash pop $stashId" $_
            addCompletion "stash apply $stashId" $_
            addCompletion "stash drop $stashId" $_
        }
    }
    return $tempList + $completions
}
