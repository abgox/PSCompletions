function handleCompletions($completions) {
    $list = @()

    $input_arr = $PSCompletions.input_arr
    $filter_input_arr = $PSCompletions.filter_input_arr # Without -*

    function return_bookmark {
        $t = @"
if(remote,
  if(tracked,
    separate(" ",
      label("bookmark", name ++ "@" ++ remote),
    ),
    label("bookmark", name ++ "@" ++ remote),
  ),
  label("bookmark", name)
) ++ "\n"
"@
        jj bookmark list --all-remotes --template $t | ForEach-Object {
            $PSCompletions.return_completion($_, "bookmark")
        }
    }

    function return_tag {
        $t = @"
if(remote,
  if(tracked,
    separate(" ",
      label("bookmark", name ++ "@" ++ remote),
    ),
    label("bookmark", name ++ "@" ++ remote),
  ),
  label("bookmark", name)
) ++ "\n"
"@
        jj tag list --template $t | ForEach-Object {
            $PSCompletions.return_completion($_, "tag")
        }
    }

    function return_common_revsets {
        "'..'", "'::'", "'@'", "'@-'", "'@+'", "'all()'"  | ForEach-Object {
            $PSCompletions.return_completion($_, "revsets")
        }
    }

    function return_revsets {
        jj log -r "present(@) | present(trunk()) | ancestors(immutable_heads().., 2)" -T 'change_id.short() ++ ": " ++ description.first_line() ++ "\n"' --no-pager --no-graph --limit 30 | ForEach-Object {
            $part = $_.Split(":", 2)
            $tip = $part[1].Trim()
            if (!$tip) {
                $tip = 'revsets'
            }
            $PSCompletions.return_completion($part[0], $tip)
        }
    }

    switch ($filter_input_arr[0]) {
        'new' {
            $list += return_common_revsets
            $list += return_revsets
            $list += return_bookmark
        }
        'bookmark' {
            switch ($filter_input_arr[1]) {
                { $_ -in 'set', 'rename', 'move', 'forget', 'delete', 'track' } {
                    $list += return_bookmark
                }
            }
        }
    }

    $argList = @(
        '-r', '--revisions',
        '-d', '--destination', # TODO: jj 的未来版本废弃了它，需要移除
        '-o', '--onto',
        '-A', '--insert-after',
        '-B', '--insert-before',
        '-f', '--from',
        '-t', '--to', '--into',
        '--range',
        '-c', '--change'
    )

    if ($input_arr[-1] -cin $argList) {
        $list += return_common_revsets
        $list += return_revsets
    }

    if ($input_arr[-1] -cin '-b', '--branch', '--bookmark') {
        $list += return_bookmark
    }

    return $list + $completions
}
