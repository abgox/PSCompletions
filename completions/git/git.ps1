if (!$PSCompletions.comp_config.git.max_commit) {
    $PSCompletions.comp_config.git = @{
        max_commit = 20
    }
}
Register-ArgumentCompleter -CommandName $PSCompletions.comp_cmd.git -ScriptBlock {
    param($word_to_complete, $command_ast, $cursor_position)

    #region : Store
    $root_cmd = $PSCompletions.comp_cmd.git

    $PSCompletions.fn_cache($PSScriptRoot)

    $completions = $PSCompletions.comp_data.$root_cmd.Clone()

    $_info = $PSCompletions.comp_data.$($root_cmd + '_info').core_info

    $need_skip = @(
        '-m', '-t', '-F', '-C', '--depth', '-b', '-j',
        '-i', '--interactive', '--soft', '--hard', '--mixed', '-d', '-v'
    )
    #endregion

    #region : Special
    try {
        $_i = 99999
        $branch_list = git branch --format='%(refname:lstrip=2)' 2>$null
        $head_list = @{
            HEAD       = (git show HEAD --relative-date -q 2>$null) -join "`n"
            FETCH_HEAD = (git show FETCH_HEAD --relative-date -q 2>$null) -join "`n"
            ORIG_HEAD  = (git show ORIG_HEAD --relative-date -q 2>$null) -join "`n"
            MERGE_HEAD = (git show MERGE_HEAD --relative-date -q 2>$null) -join "`n"
        }
        @('HEAD', 'FETCH_HEAD', 'ORIG_HEAD', 'MERGE_HEAD') | ForEach-Object {
            if (!$head_list.$_) {
                $head_list.Remove($_)
            }
        }
        $branch_head_list = $branch_list + $head_list.Keys
        $remote_list = git remote 2>$null
        $commit_info = [System.Collections.Generic.List[array]]::new()
        $current_commit = [System.Collections.Generic.List[string]]::new()

        git log --pretty='format:%h%nDate: %cr%nAuthor: %an <%ae>%n%B%n@@@--------------------@@@' -n $PSCompletions.comp_config.git.max_commit --encoding=gbk 2>$null | ForEach-Object {
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

        $branch_list | ForEach-Object {
            $info = 'branch --- ' + $_
            $info_s = $_info.symbol + $info
            $completions[ $root_cmd + ' switch ' + $_] = @($_, $info, $_i)
            $completions[ $root_cmd + ' merge ' + $_] = @($_, $info_s, $_i)
            $completions[ $root_cmd + ' diff ' + $_] = @($_, $info_s, $_i)
            $_i++
        }
        $head_list.Keys | ForEach-Object {
            $info = $head_list.$_
            $completions[ $root_cmd + ' rebase -i ' + $_] = @($_, $info, $_i)
            $completions[ $root_cmd + ' rebase --interactive ' + $_] = @($_, $info, $_i)
            $completions[ $root_cmd + ' diff ' + $_] = @($_, $info, $_i)
            $completions[ $root_cmd + ' reset ' + $_] = @($_, $info, $_i)
            $completions[ $root_cmd + ' reset --soft ' + $_] = @($_, $info, $_i)
            $completions[ $root_cmd + ' reset --hard ' + $_] = @($_, $info, $_i)
            $completions[ $root_cmd + ' reset --mixed ' + $_] = @($_, $info, $_i)
            $completions[ $root_cmd + ' show ' + $_] = @($_, $info, $_i)
            $_i++
        }
        $branch_head_list | ForEach-Object {
            $info = if ($head_list.$_) { $head_list.$_ }else { 'branch --- ' + $_ }
            $completions[ $root_cmd + ' checkout ' + $_] = @($_, $info, $_i)
            $_i++
        }
        $remote_list | ForEach-Object {
            $info = 'remote --- ' + $_
            $info_s = $_info.symbol + $info
            $completions[ $root_cmd + ' push ' + $_] = @($_, $info_s, $_i)
            $completions[ $root_cmd + ' pull ' + $_] = @($_, $info_s, $_i)
            $completions[ $root_cmd + ' fetch ' + $_] = @($_, $info_s, $_i)
            $completions[ $root_cmd + ' remote rename ' + $_] = @($_, $info, $_i)
            $completions[ $root_cmd + ' remote rm ' + $_] = @($_, $info, $_i)
            $_i++
        }
        $commit_info | ForEach-Object {
            $hash = $_[0]
            $date = $_[1]
            $author = $_[2]
            $commit = $_[3..($_.Length - 1)]
            $content = $date + "`n" + $author + "`n" + ($commit -join "`n")

            $completions[$root_cmd + ' ' + 'commit -C' + ' ' + $hash] = @($hash, $content, $_i)

            $completions[$root_cmd + ' ' + 'rebase -i' + ' ' + $hash] = @($hash, $content, $_i)
            $completions[$root_cmd + ' ' + 'rebase --interactive' + ' ' + $hash] = @($hash, $content, $_i)
            $completions[$root_cmd + ' ' + 'checkout' + ' ' + $hash] = @($hash, $content, $_i)
            $completions[$root_cmd + ' ' + 'diff' + ' ' + $hash] = @($hash, $content, $_i)
            $completions[$root_cmd + ' ' + 'reset' + ' ' + $hash] = @($hash, $content, $_i)
            $completions[$root_cmd + ' ' + 'reset --soft' + ' ' + $hash] = @($hash, $content, $_i)
            $completions[$root_cmd + ' ' + 'reset --hard' + ' ' + $hash] = @($hash, $content, $_i)
            $completions[$root_cmd + ' ' + 'reset --mixed' + ' ' + $hash] = @($hash, $content, $_i)
            $completions[$root_cmd + ' ' + 'show' + ' ' + $hash] = @($hash, $content, $_i)
            $completions[$root_cmd + ' ' + 'revert' + ' ' + $hash] = @($hash, $content, $_i)
            $completions[$root_cmd + ' ' + 'commit' + ' ' + $hash] = @($hash, $content, $_i)
            $_i++
        }
        $tag_list | ForEach-Object {
            $completions[ $root_cmd + ' tag -d ' + $_] = @($_, ('tag --- ' + $_), $_i)
            $completions[ $root_cmd + ' tag -v ' + $_] = @($_, ('tag --- ' + $_), $_i)
            $_i++
        }
    }
    catch {}

    #endregion

    #region : Running
    $orgin_input = ($command_ast.CommandElements -join ' ') -split ' '
    $input_arr = $orgin_input
    $space_tab = if (!$word_to_complete.length) { 1 }else { 0 }

    $flag = $input_arr[-1] -notin $need_skip -and $input_arr[-1] -like '-*'

    if ($space_tab) { $complete = ' ' }
    elseif ($flag) {
        $space_tab++
        $complete = ' ' + $word_to_complete
    }

    function format_input([array]$input_arr, [array]$need_skip = @()) {
        if ($input_arr.Count -eq 1) {
            return $input_arr[0]
        }
        $res = @()
        $skip = 0
        for ($i = 0; $i -lt $input_arr.Count; $i++) {
            if ($i -eq 1 -and $input_arr[$i] -in $need_skip) {
                $res += $input_arr[$i]
                continue
            }
            if ($skip -and ($i -ne $input_arr.Count - 1 -or $input_arr[$i] -notin $need_skip)) {
                if ($input_arr[$i] -notlike '-*') { $skip = 0 }
                continue
            }
            if ($input_arr[$i] -like '-*') {
                if ($input_arr[$i] -in $need_skip -and $i -eq $input_arr.Count - 1) {
                    $res += $input_arr[$i]
                    return $res
                }
                else { $skip = 1 }
            }
            else { $res += $input_arr[$i] }
        }
        return $res
    }

    $input_arr = format_input $input_arr $need_skip

    $filter_list = $completions.Keys | Where-Object {
        $cmd = $_ -split ' '
        $cmd[-1] -notin $orgin_input -and $cmd.Count -eq ($input_arr.Count + $space_tab) -and ($cmd -join ' ') -like ($input_arr -join ' ') + $complete + '*'
    } | Sort-Object { $completions.$_[-1] }

    function complete_by_old {
        $max_len = 0
        $display_count = 0
        $cmd_line = [System.Console]::WindowHeight - 5

        $filter_list | ForEach-Object {
            $completions[$_][0] = $completions[$_][0].Replace('^up', ' ')
            $len = $completions[$_][0].Length
            if ($len -ge $max_len) { $max_len = $len }
        }
        $comp_count = $cmd_line * [math]::Floor([System.Console]::WindowWidth / ($max_len + 2))
        $filter_list | ForEach-Object {
            if ($comp_count -gt $display_count) {
                $display_count++
                $item = $completions[$_][0]
                [CompletionResult]::new($item, $item, 'ParameterValue', ($PSCompletions.fn_replace($completions[$_][1])))
            }
            else {
                [CompletionResult]::new(' ', '...', 'ParameterValue', $PSCompletions.json.comp_hide)
                return
            }
        }
        if ($display_count -eq 1) { ' ' }
    }

    $filter_list | ForEach-Object {
        $completions[$_][0] = $completions[$_][0].Replace('^up', '')
    }

    if ($PSCompletions.ui.show -and $PSVersionTable.Platform -ne 'Unix') {
        $PSCompletions.ui.show()
    }
    else { complete_by_old }

    $PSCompletions.fn_order_job($PSScriptRoot, $root_cmd)
    #endregion
}
