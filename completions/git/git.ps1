using namespace System.Management.Automation
using namespace System.Management.Automation.Language
Register-ArgumentCompleter -CommandName $_psc.comp_cmd.git -ScriptBlock {
    param($wordToComplete, $commandAst)

    #region : Store
    $root_cmd = $_psc.comp_cmd.git
    $_i = 9999
    if (!$_psc.comp_data.$root_cmd) {
        $_psc.comp_data.$root_cmd = [ordered]@{}
        $json = Get-Content -Raw -Path  ($PSScriptRoot + '\json\' + $_psc.lang + '.json') -Encoding UTF8 | ConvertFrom-Json

        $_psc.comp_data.$($root_cmd + '_info') = @{
            core_info = $json.git_core_info
            exclude   = @('git_core_info')
            num       = -1
        }

        $order = $_psc.fn_get_order($PSScriptRoot, $_psc.comp_data.$($root_cmd + '_info').exclude)

        $json.PSObject.Properties.Name | Where-Object {
            $_ -notin $_psc.comp_data.$($root_cmd + '_info').exclude
        } | ForEach-Object {
            $cmd = $_ -split ' '
            $_o = if ($order.$_) { $order.$_ }else { $_i++ }
            $_psc.comp_data.$root_cmd[$root_cmd + ' ' + $_] = @($cmd[-1], $json.$_, $_o)

            $_psc.comp_data.$root_cmd[$root_cmd + ' help ' + $cmd[0] ] = @($cmd[0], ($json.git_core_info.help + ' --- ' + $cmd[0]), $_o)

        }
    }
    else {
        if ($_psc.jobs.State -eq 'Completed') {
            $_psc.comp_data = Receive-Job $_psc.jobs
        }
        try { Remove-Job $_psc.jobs }catch {}
    }

    $completions = $_psc.comp_data.$root_cmd
    $need_skip = @(
        '-m', '-t', '-F', '-C', '--depth', '-b', '-j',
        '-i', '--interactive', '--soft', '--hard', '--mixed', '-d', '-v'
    )
    #endregion

    #region : Special
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
    git log --pretty='format:%h%nDate: %cr%nAuthor: %an <%ae>%n%B%n@@@--------------------@@@'  -n 20 --encoding=GBK 2>$null | ForEach-Object {
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
        $completions[ $root_cmd + ' switch ' + $_] = @($_, $info, $_i++)
        $completions[ $root_cmd + ' merge ' + $_] = @($_, $info_s, $_i++)
        $completions[ $root_cmd + ' diff ' + $_] = @($_, $info_s, $_i++)
    }

    $head_list.Keys | ForEach-Object {
        $info = $head_list.$_
        $completions[ $root_cmd + ' rebase -i ' + $_] = @($_, $info, $_i++)
        $completions[ $root_cmd + ' rebase --interactive ' + $_] = @($_, $info, $_i++)
        $completions[ $root_cmd + ' diff ' + $_] = @($_, $info, $_i++)
        $completions[ $root_cmd + ' reset ' + $_] = @($_, $info, $_i++)
        $completions[ $root_cmd + ' reset --soft ' + $_] = @($_, $info, $_i++)
        $completions[ $root_cmd + ' reset --hard ' + $_] = @($_, $info, $_i++)
        $completions[ $root_cmd + ' reset --mixed ' + $_] = @($_, $info, $_i++)
        $completions[ $root_cmd + ' show ' + $_] = @($_, $info, $_i++)
    }

    $branch_head_list | ForEach-Object {
        $info = if ($head_list.$_) { $head_list.$_ }else { 'branch --- ' + $_ }
        $completions[ $root_cmd + ' checkout ' + $_] = @($_, $info, $_i++)
    }

    $remote_list | ForEach-Object {
        $info = 'remote --- ' + $_
        $info_s = $symbol + $info
        $completions[ $root_cmd + ' push ' + $_] = @($_, $info_s, $_i++)
        $completions[ $root_cmd + ' pull ' + $_] = @($_, $info_s, $_i++)
        $completions[ $root_cmd + ' fetch ' + $_] = @($_, $info_s, $_i++)
        $completions[ $root_cmd + ' remote rename ' + $_] = @($_, $info, $_i++)
        $completions[ $root_cmd + ' remote rm ' + $_] = @($_, $info, $_i++)
    }

    $commit_info | ForEach-Object {
        $hash = $_[0]
        $date = $_[1]
        $author = $_[2]
        $commit = $_[3..($_.Length - 1)]
        $content = $date + "`n" + $author + "`n" + ($commit -join "`n")

        $completions[$root_cmd + ' ' + 'commit -C' + ' ' + $hash] = @($hash, $content, $_i++)


        $completions[$root_cmd + ' ' + 'rebase -i' + ' ' + $hash] = @($hash, $content, $_i++)
        $completions[$root_cmd + ' ' + 'rebase --interactive' + ' ' + $hash] = @($hash, $content, $_i++)
        $completions[$root_cmd + ' ' + 'checkout' + ' ' + $hash] = @($hash, $content, $_i++)
        $completions[$root_cmd + ' ' + 'diff' + ' ' + $hash] = @($hash, $content, $_i++)
        $completions[$root_cmd + ' ' + 'reset' + ' ' + $hash] = @($hash, $content, $_i++)
        $completions[$root_cmd + ' ' + 'reset --soft' + ' ' + $hash] = @($hash, $content, $_i++)
        $completions[$root_cmd + ' ' + 'reset --hard' + ' ' + $hash] = @($hash, $content, $_i++)
        $completions[$root_cmd + ' ' + 'reset --mixed' + ' ' + $hash] = @($hash, $content, $_i++)
        $completions[$root_cmd + ' ' + 'show' + ' ' + $hash] = @($hash, $content, $_i++)
        $completions[$root_cmd + ' ' + 'revert' + ' ' + $hash] = @($hash, $content, $_i++)
        $completions[$root_cmd + ' ' + 'commit' + ' ' + $hash] = @($hash, $content, $_i++)
    }

    $tag_list | ForEach-Object {
        $completions[ $root_cmd + ' tag -d ' + $_] = @($_, ('tag --- ' + $_), $_i++)
        $completions[ $root_cmd + ' tag -v ' + $_] = @($_, ('tag --- ' + $_), $_i++)
    }
    #endregion


    #region : Running
    $input_str = $commandAst.CommandElements -join ' '
    $input_arr = $input_str -split ' '
    $space_tab = if (!$wordToComplete.length) { 1 }else { 0 }

    $flag = $input_arr[-1] -notin $need_skip -and $input_arr[-1] -like '-*'
    if (!$space_tab -and $flag) {
        $space_tab++
        $complete = ' ' + $wordToComplete
    }
    else { $complete = '' }

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
                else {
                    $skip = 1
                }
            }
            else { $res += $input_arr[$i] }
        }
        return $res
    }

    $input_arr = format_input $input_arr $need_skip

    $max_len = 0
    $display_count = 0
    $cmd_line = [System.Console]::WindowHeight - 5
    $filter_list = $completions.Keys | Where-Object {
        $cmd = $_ -split ' '
        $cmd.Count -eq ($input_arr.Count + $space_tab) -and ($cmd -join ' ') -like ($input_arr -join ' ') + $complete + '*'
    }

    $filter_list = $filter_list | Sort-Object { $completions.$_[-1] }

    $filter_list | ForEach-Object {
        $completions[$_][0] = $completions[$_][0].Replace('^up', ' ')
        $len = $completions[$_][0].Length
        if ($len -ge $max_len) { $max_len = $len }
    }

    $comp_count = $cmd_line * [math]::Floor([System.Console]::WindowWidth / ($max_len + 2))

    $json_info = $_psc.comp_data.$($root_cmd + '_info').core_info
    $filter_list | ForEach-Object {
        if ($comp_count -gt $display_count) {
            $display_count++
            $item = $completions[$_][0]
            [CompletionResult]::new($item, $item, 'ParameterValue', ($_psc.fn_replace($completions[$_][1])))
        }
        else {
            [CompletionResult]::new(' ', '...', 'ParameterValue', $_psc.json.comp_hide)
            return
        }
    }
    if ($display_count -eq 1) { ' ' }
    #endregion

    #region : Back
    $_psc.jobs = Start-Job -ScriptBlock {
        param(
            $_psc,
            $cmd,
            $PSScriptRoots,
            $path_history
        )
        # LRU
        if ($_psc.comp_data.Count -gt [int]$_psc.config.LRU * 2) {
            $_psc.comp_data.RemoveAt(0)
            $_psc.comp_data.RemoveAt(0)
        }
        try {
            $history = [array](Get-Content $path_history | Where-Object { ($_ -split '\s+')[0] -eq $cmd })
            $history = $history[-1] -split ' '

            function fn([array]$history) {
                $_i = 0
                $res = @()
                $history | ForEach-Object {
                    if ($_ -like '-*') {
                        $res += $_i
                    }
                    $_i++
                }
                return $res[0]
            }

            $i = fn $history
            if ($i) {
                $prefix = $history[0..($i - 1)] -join ' '
                $history[$i..($history.Count - 1)] | ForEach-Object {
                    try {
                        $_psc.comp_data.$cmd.$($prefix + ' ' + $_)[-1] = $_psc.comp_data.$($cmd + '_info').num--
                    }
                    catch {}
                }
                $base = $prefix -split ' '
            }
            else {
                $base = $history
            }

            while ($base.Count -gt 1) {
                try {
                    $_psc.comp_data.$cmd.$($base -join ' ')[-1] = $_psc.comp_data.$($cmd + '_info').num--
                }
                catch {}
                $base = $base[0..($base.Count - 2)]
            }
        }
        catch {}

        $json_order = (Get-Content -Raw -Path ($PSScriptRoots + '\json\' + $_psc.lang + '.json') -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties.Name | Where-Object { $_ -notin $_psc.comp_data.$($cmd + '_info').exclude }  | Sort-Object {
            $_psc.comp_data.$cmd.$($cmd + ' ' + $_)[-1]
        }
        $path_order = $PSScriptRoots + '\order.json'
        $order_old = (Get-Content -Raw -Path ($path_order) | ConvertFrom-Json).PSObject.Properties.Name

        if (($json_order -join ' ') -ne ($order_old -join ' ')) {
            $i = 1
            $order = [ordered]@{}
            $json_order | ForEach-Object {
                $order.$_ = $i++
            }
            $order | ConvertTo-Json | Out-File $path_order -Force
        }
        return $_psc.comp_data
    }  -ArgumentList $_psc, $root_cmd, $PSScriptRoot, (Get-PSReadLineOption).HistorySavePath
    #endregion
}
