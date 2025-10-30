function handleCompletions($completions) {
    $list = @()

    # $input_arr = $PSCompletions.input_arr
    $filter_input_arr = $PSCompletions.filter_input_arr # Without -*

    # example
    switch ($filter_input_arr[-1]) {
        'add' {
            $list += $PSCompletions.return_completion('abc', "Add abc")
        }
    }

    return $list + $completions
}
