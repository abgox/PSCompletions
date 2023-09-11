using namespace System.Globalization
using namespace System.Management.Automation
using namespace System.Management.Automation.Language
Register-ArgumentCompleter -CommandName $_psc.comp_cmd.git -ScriptBlock {
    param($wordToComplete, $commandAst)

    $root_cmd = $_psc.comp_cmd.git

    #region : Parse json data
    $_name = $PSScriptRoot + '\json\' + $_psc.lang + '.json'
    $_json = (Get-Content -Raw -Path  $_name -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties
    #endregion

    #region : Store
    $completions = [ordered]@{}
    $_json | ForEach-Object {
        if ($_.Name -ne 'git_core_info') {
            $last_cmd = $_.Name.substring($_.Name.lastIndexOf(' ') + 1)
            $completions[$root_cmd + ' ' + $_.Name] = @($last_cmd, $_.Value)
            $completions[$root_cmd + ' help ' + $_.Name] = @($last_cmd, ('Show help -- ' + $last_cmd))
        }
    }
    #endregion

    #region Special point
    $branch_list = git branch 2>$null
    $head_list = [System.Collections.Generic.List[string]]@('HEAD', 'FETCH_HEAD', 'ORIG_HEAD', 'MERGE_HEAD')
    $head_lists = $head_list
    if ($branch_list) {
        ($branch_list -replace '\*', '').Trim() | ForEach-Object {
            $completions[ $root_cmd + ' branch ' + $_] = @($_, ('branch -- ' + $_) )
        }
        $head_lists = ($branch_list -replace '\*', '').Trim() + $head_list
    }
    $head_lists | ForEach-Object {
        $completions[ $root_cmd + ' checkout ' + $_] = @($_, '...')
        $completions[ $root_cmd + ' cherry ' + $_] = @($_, '...')
        $completions[ $root_cmd + ' cherry-pick ' + $_] = @($_, '...')
        $completions[ $root_cmd + ' archive ' + $_] = @($_, '...')
        $completions[ $root_cmd + ' diff ' + $_] = @($_, '...')
        $completions[ $root_cmd + ' difftool ' + $_] = @($_, '...')
        $completions[ $root_cmd + ' log ' + $_] = @($_, '...')
        $completions[ $root_cmd + ' merge ' + $_] = @($_, '...')
        $completions[ $root_cmd + ' mergetool ' + $_] = @($_, '...')
        $completions[ $root_cmd + ' rebase ' + $_] = @($_, '...')
        $completions[ $root_cmd + ' reset ' + $_] = @($_, '...')
        $completions[ $root_cmd + ' revert ' + $_] = @($_, '...')
        $completions[ $root_cmd + ' show ' + $_] = @($_, '...')
        $completions[ $root_cmd + ' switch ' + $_] = @($_, '...')


        $completions[ $root_cmd + ' bisect good ' + $_] = @($_, '...')
        $completions[ $root_cmd + ' bisect bad ' + $_] = @($_, '...')
        $completions[ $root_cmd + ' bisect new ' + $_] = @($_, '...')
        $completions[ $root_cmd + ' bisect old ' + $_] = @($_, '...')
        $completions[ $root_cmd + ' bisect skip ' + $_] = @($_, '...')
        $completions[ $root_cmd + ' bisect start ' + $_] = @($_, '...')

        $completions[ $root_cmd + ' bisect reset ' + $_] = @($_, '...')

        $completions[ $root_cmd + ' blame ' + $_] = @($_, '...')
        $completions[ $root_cmd + ' check-ref-format ' + $_] = @($_, '...')
        $completions[ $root_cmd + ' cherry ' + $_] = @($_, '...')
    }

    #region get commit info
    $commit_info = [System.Collections.Generic.List[System.Object]]@()
    $commit = $null
    $flag = 1
    git log | ForEach-Object {
        $line = $_
        if ($line -match '^\s*commit\s*(\w+)') {
            if ($commit) {
                $info = $commit.info | Where-Object { $_ -ne '' }
                if ($info.Count -gt 10) {
                    $info = $info[0..9]
                    $info += '...'
                }
                $commit.info = $info -join "`n"
                $commit_info.Add($commit)
                $flag = 1
            }
            $commit = @{
                hash = ($Matches[1]).Substring(0, 7)
                info = @()
            }
        }
        elseif ($commit) {
            if ($line -match '^Author:\s*(.+)') {
                $commit.author = $Matches[1].Trim()
            }
            elseif ($line -match '^Date:\s*(.+)') {
                $commit.Date = $Matches[1].Trim()
            }
            else {
                if ($line) {
                    if ($flag) {
                        $commit.space = ([regex]::Matches($line, "(\s*)\S"))[0].Length - 1
                        $flag = $null
                    }
                    $commit.info += $line.Substring($commit.space)
                }
            }
        }
    }
    $commit_info.Add($commit)
    $_psc.test = $commit_info
    #endregion

    if ($commit_info) {
        $commit_info | ForEach-Object {
            $content = _psc_replace ('Date: ' + $_.date + "`n" + $_.info)
            $completions[ $root_cmd + ' checkout ' + $_.hash] = @($_.hash, $content)
            $completions[ $root_cmd + ' switch ' + $_.hash] = @($_.hash, $content)
            $completions[ $root_cmd + ' archive ' + $_.hash] = @($_.hash, $content)

            $completions[ $root_cmd + ' bisect good ' + $_.hash] = @($_.hash, $content)
            $completions[ $root_cmd + ' bisect bad ' + $_.hash] = @($_.hash, $content)
            $completions[ $root_cmd + ' bisect new ' + $_.hash] = @($_.hash, $content)
            $completions[ $root_cmd + ' bisect old ' + $_.hash] = @($_.hash, $content)
            $completions[ $root_cmd + ' bisect skip ' + $_.hash] = @($_.hash, $content)
            $completions[ $root_cmd + ' bisect start ' + $_.hash] = @($_.hash, $content)
            $completions[ $root_cmd + ' blame ' + $_.hash] = @($_.hash, $content)
            $completions[ $root_cmd + ' cherry ' + $_.hash] = @($_.hash, $content)
        }
    }
    #endregion

    #region : Carry out
    $_input = $commandAst.CommandElements
    $_input_str = $_input -join ' '
    $_input_arr = $_input_str -split '\s+'
    $limit_value = 0
    $limit_line = 0
    $display_count = 0
    $cmd_line = [System.Console]::WindowHeight - 4
    $input_tab = if (!$wordToComplete.length) { 1 }else { 0 }
    $filter_list = $completions.Keys | Where-Object {
        $cmd = $_ -split '\s+'
        $position = [System.Collections.Generic.List[int]]@()
        for ($i = 0; $i -lt $cmd.Count; $i++) {
            if ($cmd[$i] -match "<.+>") { $position.Add($i) }
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
        $len = $completions[$_][0].Length
        if ($len -ge $limit_value) { $limit_value = $len }
        $line = ($completions[$_][1] -split "`n").Count
        if ($line -ge $limit_line) { $limit_line = $line }
    }
    $comp_count = ($cmd_line - $limit_line) * [math]::Floor([System.Console]::WindowWidth / ($limit_value + 2))

    if ($comp_count -le [math]::Floor($filter_list.Count / 3)) {
        $comp_count = $cmd_line * [math]::Floor([System.Console]::WindowWidth / ($limit_value + 2))
    }

    $filter_list | ForEach-Object {
        if ($comp_count -gt $display_count) {
            $display_count++
            [CompletionResult]::new($completions[$_][0], $completions[$_][0], 'ParameterValue', (_psc_replace $completions[$_][1]))
        }
        else {
            [CompletionResult]::new(" ", "...", 'ParameterValue', $_psc.json.comp_hide)
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
