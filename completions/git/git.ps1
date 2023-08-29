using namespace System.Globalization
using namespace System.Management.Automation
using namespace System.Management.Automation.Language
Register-ArgumentCompleter -CommandName $_psc.comp_cmd.git -ScriptBlock {
    param($wordToComplete, $commandAst)

    $completions = [System.Collections.Specialized.OrderedDictionary]::new()
    $root_cmd = $_psc.comp_cmd.git

    #region : Parse json data
    $_name = $PSScriptRoot + '\json\' + $_psc.lang + '.json'
    $_json = (Get-Content -Raw -Path  $_name -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties
    #endregion

    #region : Store
    $max_len = 0
    foreach ($_ in $_json) {
        $subCmd = $_.Name.substring($_.Name.lastIndexOf(' ') + 1)
        if ($max_len -lt $subCmd.length) {
            $max_len = $subCmd.length
        }
        $completions[$root_cmd + ' ' + $_.Name] = [CompletionResult]::new($subcmd, $subcmd, 'ParameterValue', (_psc_replace $_.value))
        $completions[$root_cmd + ' help ' + $_.Name] = [CompletionResult]::new($subcmd, $subcmd, 'ParameterValue', '...')

    }
    #endregion

    #region : Special point
    function format_time($time) {
        $givenDate = [DateTime]::ParseExact($time, "ddd MMM dd HH:mm:ss yyyy zzz", [CultureInfo]::InvariantCulture)
        $relativeTime = (Get-Date) - $givenDate
        if ($relativeTime.Days -gt 0) {
            $relativeValue = "$($relativeTime.Days)d ago"
        }
        elseif ($relativeTime.Hours -gt 0) {
            $relativeValue = "$($relativeTime.Hours)h ago"
        }
        elseif ($relativeTime.Minutes -gt 0) {
            $relativeValue = "$($relativeTime.Minutes)m ago"
        }
        else {
            $relativeValue = "just now"
        }
        return $relativeValue
    }

    $commit_info = @()
    $commit_arr = (((git log ) -join '') -split "(?=commit \w{20,})") | Where-Object { $_ -ne '' }
    foreach ($item in $commit_arr) {
        $pattern = "commit (.*)Author:(.*).*Date:(.*)   (.*)"
        $matches = [regex]::Matches($item, $pattern)
        foreach ($m in $matches) {
            $commit_info += @{
                'hash'   = (($m.Groups[1].Value).Trim()).Substring(0, 6)
                'author' = ($m.Groups[2].Value).Trim()
                'date'   = format_time ($m.Groups[3].Value).Trim()
                'info'   = ($m.Groups[4].Value).Trim()
            }
        }
    }

    foreach ($_ in $commit_info) {
        $completions[ $root_cmd + ' checkout ' + $_.hash] = [CompletionResult]::new($_.hash, $_.hash, 'ParameterValue', (_psc_replace ($_.info + '(' + $_.date + ')')) )
        $completions[ $root_cmd + ' switch ' + $_.hash] = [CompletionResult]::new($_.hash, $_.hash, 'ParameterValue', (_psc_replace ($_.info + '(' + $_.date + ')')) )
    }

    $branch_list = git branch 2>$null
    if ($branch_list) {
        ($branch_list -replace '\*', '').Trim() | ForEach-Object {
            $completions[ $root_cmd + ' branch ' + $_] = [CompletionResult]::new($_, $_, 'ParameterValue', '...')
        }
        ($branch_list -replace '\*', '').Trim() + @('HEAD', 'FETCH_HEAD', 'ORIG_HEAD', 'MERGE_HEAD') | ForEach-Object {
            $completions[ $root_cmd + ' checkout ' + $_] = [CompletionResult]::new($_, $_, 'ParameterValue', '...')
            $completions[ $root_cmd + ' cherry ' + $_] = [CompletionResult]::new($_, $_, 'ParameterValue', '...')
            $completions[ $root_cmd + ' cherry-pick ' + $_] = [CompletionResult]::new($_, $_, 'ParameterValue', '...')
            $completions[ $root_cmd + ' diff ' + $_] = [CompletionResult]::new($_, $_, 'ParameterValue', '...')
            $completions[ $root_cmd + ' difftool ' + $_] = [CompletionResult]::new($_, $_, 'ParameterValue', '...')
            $completions[ $root_cmd + ' log ' + $_] = [CompletionResult]::new($_, $_, 'ParameterValue', '...')
            $completions[ $root_cmd + ' merge ' + $_] = [CompletionResult]::new($_, $_, 'ParameterValue', '...')
            $completions[ $root_cmd + ' mergetool ' + $_] = [CompletionResult]::new($_, $_, 'ParameterValue', '...')
            $completions[ $root_cmd + ' rebase ' + $_] = [CompletionResult]::new($_, $_, 'ParameterValue', '...')
            $completions[ $root_cmd + ' reset ' + $_] = [CompletionResult]::new($_, $_, 'ParameterValue', '...')
            $completions[ $root_cmd + ' revert ' + $_] = [CompletionResult]::new($_, $_, 'ParameterValue', '...')
            $completions[ $root_cmd + ' show ' + $_] = [CompletionResult]::new($_, $_, 'ParameterValue', '...')
            $completions[ $root_cmd + ' switch ' + $_] = [CompletionResult]::new($_, $_, 'ParameterValue', '...')
        }
    }
    #endregion

    #region : Carry out
    $comp_num = ([System.Console]::WindowHeight - 2) * ([math]::Floor([System.Console]::WindowWidth / ($max_len + 2)))
    $_input = $commandAst.CommandElements
    function _do($num) {
        $i = 0
        $completions.Keys | Where-Object { $_ -like "$_input*" } | ForEach-Object {
            $input_space_count = ($_input -split ' ').Count - 1
            $cmd_space_count = ($_ -split ' ').Count - 1
            if ($input_space_count -eq $cmd_space_count + $num ) {
                $i++
                if ($comp_num -gt $i) { $completions[$_] }
                else {
                    [CompletionResult]::new(" ", "...", 'ParameterValue', "...")
                    return
                }
            }
        }
    }
    _do $(if ($wordToComplete.length) { 0 }else { -1 })
    #endregion

    #region
    try {
        $history = (Get-History)[-1].CommandLine
    }
    catch {
        $history = ''
    }
    $null = Start-Job -ScriptBlock {
        param( $_psc, $history, $root)
        function _do($flag, $path) {
            $json = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
            $res = [ordered]@{}
            $max = 0
            $cmd_len = 0
            $res_flag = $null
            foreach ($_ in $json.PSObject.Properties) {
                $type = ($_.value).GetType().Name
                if ($type -eq 'String') {
                    $cmd = $_.Name -split ' '
                    $count = (Compare-Object $cmd $flag -IncludeEqual -ExcludeDifferent -PassThru).Count
                    if ($count -gt $max) {
                        $cmd_len = $cmd.Count
                        $max = $count
                        $res_flag = $_.Name
                    }
                    elseif ($count -eq $max) {
                        if ($cmd_len -gt $cmd.Count) {
                            $max = $count
                            $res_flag = $_.Name
                        }
                    }
                }
            }
            foreach ($_ in $json.PSObject.Properties) {
                $type = ($_.value).GetType().Name
                if ($type -eq 'String') {
                    if ($_.Name -eq $res_flag) {
                        $res.Insert(0, $_.Name, $_.value)
                    }
                    else { $res.($_.Name) = $_.value }
                }
                else { $res.($_.Name) = $_.value }
            }
            $res  | ConvertTo-Json | Out-File $path
        }
        if ($history -ne '') {
            $cmd = $history -split ' '
            $alias = $_psc.comp_cmd.keys | foreach-Object { $_psc.comp_cmd.$_ }
            if ($cmd[0] -in $alias) {
                _do $cmd[1..($cmd.Length - 1)] ($root + '\json\' + $_psc.lang + '.json')
            }
        }
    } -ArgumentList $_psc, $history, $PSScriptRoot
    #endregion
}
