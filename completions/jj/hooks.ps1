function handleCompletions($completions) {
    $list = @()

    # $input_arr = $PSCompletions.input_arr
    $filter_input_arr = $PSCompletions.filter_input_arr # Without -*

    function return_bookmark {
        return jj bookmark list 2>$null | ForEach-Object { $_.split(':')[0] }
    }

    switch ($filter_input_arr[0]) {
        'new' {
            $bookmark_list = return_bookmark
            foreach ($_ in $bookmark_list) {
                $list += $PSCompletions.return_completion($_, "Bookmark: " + $_)
            }
        }
        'bookmark' {
            switch ($filter_input_arr[1]) {
                { $_ -in 'set', 'rename', 'move', 'forget', 'delete' } {
                    $bookmark_list = return_bookmark
                    foreach ($_ in $bookmark_list) {
                        $list += $PSCompletions.return_completion($_, "Bookmark: " + $_)
                    }
                }
            }
        }
    }
    return $list + $completions
}
