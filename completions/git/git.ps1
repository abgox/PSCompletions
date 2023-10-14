using namespace System.Management.Automation
using namespace System.Management.Automation.Language
Register-ArgumentCompleter -CommandName $_psc.comp_cmd.git -ScriptBlock {
    param($wordToComplete, $commandAst)

    $root_cmd = $_psc.comp_cmd.git

    #region : Store
    $json = _psc_parse_json_with_LRU $PSScriptRoot
    $json_info = $json.git_core_info
    $completions = [ordered]@{}
    _psc_generate_order $PSScriptRoot | ForEach-Object {
        if ($_ -ne 'git_core_info') {
            $cmd = $_ -split ' '
            $completions[$root_cmd + ' ' + $_] = @($cmd[-1], $json.$_)
            $completions[$root_cmd + ' help ' + $cmd[0]] = @($cmd[0], ('Show help -- ' + $cmd[0]))
        }
    }
    #endregion

    #region Special point
    $symbol = $json_info.symbol
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
    git log --pretty='format:%h%nDate: %cr%nAuthor: %an <%ae>%n%B%n@@@--------------------@@@'  -n 30 --encoding=GBK 2>$null | ForEach-Object {
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
        $info_s = $symbol + $info
        $completions[ $root_cmd + ' push <remote> ' + $_ ] = @($_, $info)
        $completions[ $root_cmd + ' pull <remote> ' + $_ ] = @($_, $info)
        $completions[ $root_cmd + ' fetch <remote> ' + $_ ] = @($_, $info)
        $completions[ $root_cmd + ' switch ' + $_] = @($_, $info)
        $completions[ $root_cmd + ' merge ' + $_] = @($_, $info_s)
        $completions[ $root_cmd + ' diff ' + $_] = @($_, $info_s)
        $completions[ $root_cmd + ' diff <branch> ' + $_] = @($_, $info)
    }

    $head_list.Keys | ForEach-Object {
        $info = $head_list.$_
        $completions[ $root_cmd + ' rebase -i ' + $_] = @($_, $info)
        $completions[ $root_cmd + ' rebase --interactive ' + $_] = @($_, $info)
        $completions[ $root_cmd + ' diff ' + $_] = @($_, $info)
        $completions[ $root_cmd + ' reset ' + $_] = @($_, $info)
        $completions[ $root_cmd + ' reset --soft ' + $_] = @($_, $info)
        $completions[ $root_cmd + ' reset --hard ' + $_] = @($_, $info)
        $completions[ $root_cmd + ' reset --mixed ' + $_] = @($_, $info)
        $completions[ $root_cmd + ' show ' + $_] = @($_, $info)
    }

    $branch_head_list | ForEach-Object {
        $info = if ($head_list.$_) { $head_list.$_ }else { 'branch --- ' + $_ }
        $completions[ $root_cmd + ' checkout ' + $_] = @($_, $info)
    }

    $remote_list | ForEach-Object {
        $info = 'remote --- ' + $_
        $info_s = $symbol + $info
        $completions[ $root_cmd + ' push ' + $_] = @($_, $info_s)
        $completions[ $root_cmd + ' pull ' + $_] = @($_, $info_s)
        $completions[ $root_cmd + ' fetch ' + $_] = @($_, $info_s)
        $completions[ $root_cmd + ' remote rename ' + $_] = @($_, $info)
        $completions[ $root_cmd + ' remote rm ' + $_] = @($_, $info)
    }

    $commit_info | ForEach-Object {
        $hash = $_[0]
        $date = $_[1]
        $author = $_[2]
        $commit = $_[3..($_.Length - 1)]
        $content = $date + "`n" + $author + "`n" + ($commit -join "`n")
        function _do($cmd, $tip) {
            $completions[$root_cmd + ' ' + $cmd + ' ' + $hash] = @($hash, $tip)
        }
        _do 'commit -C' $content
        _do 'rebase -i' $content
        _do 'rebase --interactive' $content
        _do 'checkout' $content
        _do 'diff' $content
        _do 'diff <commit>' $content
        _do 'reset' $content
        _do 'reset --soft' $content
        _do 'reset --hard' $content
        _do 'reset --mixed' $content
        _do 'show' $content
        _do 'revert' $content
        _do 'commit' $content
    }

    $tag_list | ForEach-Object {
        $completions[ $root_cmd + ' tag -d ' + $_] = @($_, 'tag --- ' + $_)
        $completions[ $root_cmd + ' tag -v ' + $_] = @($_, 'tag --- ' + $_)
    }
    #endregion

    #region : Carry out
    $_input = $commandAst.CommandElements
    $_input_str = $_input -join ' '
    $_input_arr = $_input_str -split '\s+'
    $max_len = 0
    $display_count = 0
    $cmd_line = [System.Console]::WindowHeight - 5
    $input_tab = if (!$wordToComplete.length) { 1 }else { 0 }
    $filter_list = $completions.Keys | Where-Object {
        $cmd = $_ -split '\s+'
        $position = [System.Collections.Generic.List[int]]@()
        for ($i = 0; $i -lt $cmd.Count; $i++) {
            if ($cmd[$i] -match '<.+>') { $position.Add($i) }
        }
        $_inputs = [System.Collections.Generic.List[string]]$_input_arr
        $flag = [System.Collections.Generic.List[string]]$cmd
        $position | ForEach-Object {
            if ($_inputs.Count -gt $_) {
                $flag.RemoveAt($_)
                $_inputs.RemoveAt($_)
            }
        }
        $cmd.Count -eq ($_input.Count + $input_tab) -and ($flag -join ' ') -like ($_inputs -join ' ') + '*'
    }
    $filter_list | ForEach-Object {
        $len = ($completions[$_][0].Replace('^up', ' ')).Length
        if ($len -ge $max_len) { $max_len = $len }
    }

    $comp_count = $cmd_line * [math]::Floor([System.Console]::WindowWidth / ($max_len + 2))

    $filter_list | ForEach-Object {
        if ($comp_count -gt $display_count) {
            $display_count++
            $display = $completions[$_][0].Replace('^up', ' ')
            [CompletionResult]::new($display, $display, 'ParameterValue', (_psc_replace $completions[$_][1]))
        }
        else {
            [CompletionResult]::new(' ', '...', 'ParameterValue', $_psc.json.comp_hide)
            return
        }
    }
    if ($display_count -eq 1) { echo ' ' }
    #endregion

    #region Reorder completion
    $history = try { (Get-History)[-1].CommandLine }catch { '' }
    _psc_reorder_tab $history $PSScriptRoot
    #endregion
}
