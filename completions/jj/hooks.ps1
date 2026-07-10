function handleCompletions($completions) {
    if ($PSCompletions.pending.text -like '-*') {
        return $completions
    }
    $list = [System.Collections.Generic.List[object]]::new()
    $tokens = @($PSCompletions.tokens)
    # $tokens_text = @($tokens.text)
    $cmds = @($tokens | Where-Object type -EQ 'command')
    # $cmds_text = @($cmds.text)
    $opts = @($tokens | Where-Object type -EQ 'option')
    # $opts_text = @($opts.text)
    $unknown = @($tokens | Where-Object type -EQ 'unknown')
    $unknown_text = @($unknown.text)
    function add {
        param([string]$completion, [array]$tip = $completion, [array]$symbol = @(), [switch]$noSkip)
        if ((-not $completion -or -not $noSkip) -and ($completion -in $unknown_text -or ($PSCompletions.pending -and $completion -notlike "$($PSCompletions.pending.text)*"))) { return }
        $list.Add($PSCompletions.return_completion($completion, $tip, $symbol))
    }
    function add_bookmark {
        $t = @'
if(remote,
  if(tracked,
    separate(" ",
      label("bookmark", name ++ "@" ++ remote),
    ),
    label("bookmark", name ++ "@" ++ remote),
  ),
  label("bookmark", name)
) ++ "\n"
'@
        jj bookmark list --all-remotes --template $t 2>$null | ForEach-Object {
            add $_ "bookmark --- $_"
        }
    }
    function add_tag {
        $t = @'
if(remote,
  if(tracked,
    separate(" ",
      label("bookmark", name ++ "@" ++ remote),
    ),
    label("bookmark", name ++ "@" ++ remote),
  ),
  label("bookmark", name)
) ++ "\n"
'@
        jj tag list --template $t 2>$null | ForEach-Object {
            add $_ "tag --- $_"
        }
    }
    function add_common_revsets {
        "'..'", "'::'", "'@'", "'@-'", "'@+'", "'all()'" | ForEach-Object {
            add $_ "revsets --- $_"
        }
    }
    function add_revsets {
        jj log -r 'present(@) | present(trunk()) | ancestors(immutable_heads().., 2)' -T 'change_id.short() ++ ": " ++ description.first_line() ++ "\n"' --no-pager --no-graph --limit 30 2>$null | ForEach-Object {
            $part = $_.Split(':', 2)
            $tip = $part[1].Trim()
            if (!$tip) {
                $tip = '(no description set)'
            }
            add $part[0] $tip
        }
    }
    function add_remote {
        jj git remote list 2>$null | ForEach-Object {
            $part = $_.Split(' ', 2)
            $tip = $part[1].Trim()
            $PSCompletions.return_completion($part[0], $part[1])
        }
    }

    switch ($cmds[0].text) {
        'new' {
            add_common_revsets
            add_revsets
            add_bookmark
        }
        'bookmark' {
            if ($unknown.Count -eq 0 -and $cmds[1].text -in 'set', 'rename', 'move', 'forget', 'delete', 'track') {
                add_bookmark
            }
        }
        'git' {
            if ($unknown.Count -eq 0 -and $cmds[1].text -eq 'remote' -and $cmds[2].text -in 'remove', 'rename', 'set-url') {
                add_remote
            }
        }
    }

    $argList = @(
        '-r', '--revisions',
        '-o', '--onto',
        '-A', '--insert-after',
        '-B', '--insert-before',
        '-f', '--from',
        '-t', '--to', '--into',
        '--range',
        '-c', '--change'
    )

    if ($opts[-1].text -cin $argList) {
        add_common_revsets
        add_revsets
    }

    if ($opts[-1].text -cin '-b', '--branch', '--bookmark') {
        add_bookmark
    }

    return $list + $completions
}
