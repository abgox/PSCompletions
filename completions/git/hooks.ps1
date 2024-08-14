function handleCompletions($completions) {
    $tempList = @()
    function returnCompletion($name, $tip = ' ', $symbol = '') {
        $symbols = foreach ($c in ($symbol -split ' ')) { $PSCompletions.config."symbol_$($c)" }
        $symbols = $symbols -join ''
        $padSymbols = if ($symbols) { "$($PSCompletions.config.menu_between_item_and_symbol)$($symbols)" }else { '' }
        $cmd_arr = $name -split ' '

        @{
            name           = $name
            ListItemText   = "$($cmd_arr[-1])$($padSymbols)"
            CompletionText = $cmd_arr[-1]
            ToolTip        = $tip
        }
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
        $tempList += returnCompletion "switch $($_)" $info
        $tempList += returnCompletion "branch $($_)" $info
        $tempList += returnCompletion "merge $($_)" $info
        $tempList += returnCompletion "diff $($_)" $info
    }
    foreach ($_ in $head_list.Keys) {
        $info = $head_list.$_
        $tempList += returnCompletion "rebase -i $($_)" $info
        $tempList += returnCompletion "rebase --interactive $($_)" $info
        $tempList += returnCompletion "diff $($_)" $info
        $tempList += returnCompletion "reset $($_)" $info
        $tempList += returnCompletion "reset --soft $($_)" $info
        $tempList += returnCompletion "reset --hard $($_)" $info
        $tempList += returnCompletion "reset --mixed $($_)" $info
        $tempList += returnCompletion "show $($_)" $info
    }
    foreach ($_ in $branch_head_list) {
        $info = if ($head_list.$_) { $head_list.$_ }else { 'branch --- ' + $_ }
        $tempList += returnCompletion "checkout $($_)" $info
    }
    foreach ($_ in $remote_list) {
        $info = 'remote --- ' + $_
        $tempList += returnCompletion "push $($_)" $info
        $tempList += returnCompletion "pull $($_)" $info
        $tempList += returnCompletion "fetch $($_)" $info
        $tempList += returnCompletion "remote rename $($_)" $info
        $tempList += returnCompletion "remote rm $($_)" $info
    }
    foreach ($_ in $commit_info) {
        $hash = $_[0]
        $date = $_[1]
        $author = $_[2]
        $commit = $_[3..($_.Length - 1)]
        $content = $date + "`n" + $author + "`n" + ($commit -join "`n")

        $tempList += returnCompletion "commit -C $($hash)" $content
        $tempList += returnCompletion "rebase -i $($hash)" $content
        $tempList += returnCompletion "rebase --interactive $($hash)" $content
        $tempList += returnCompletion "checkout $($hash)" $content
        $tempList += returnCompletion "diff $($hash)" $content
        $tempList += returnCompletion "reset $($hash)" $content
        $tempList += returnCompletion "reset --soft $($hash)" $content
        $tempList += returnCompletion "reset --hard $($hash)" $content
        $tempList += returnCompletion "reset --mixed $($hash)" $content
        $tempList += returnCompletion "show $($hash)" $content
        $tempList += returnCompletion "revert $($hash)" $content
        $tempList += returnCompletion "commit $($hash)" $content
    }
    foreach ($_ in $tag_list) {
        $tempList += returnCompletion "tag -d $($_)" "tag --- $($_)"
        $tempList += returnCompletion "tag -v $($_)" "tag --- $($_)"
    }
    foreach ($_ in git stash list --encoding=gbk 2>$null) {
        if ($_ -match 'stash@\{(\d+)\}') {
            $stashId = $matches[1]
            $tempList += returnCompletion "stash show $stashId" $_
            $tempList += returnCompletion "stash pop $stashId" $_
            $tempList += returnCompletion "stash apply $stashId" $_
            $tempList += returnCompletion "stash drop $stashId" $_
        }
    }
    return $tempList + $completions
}
