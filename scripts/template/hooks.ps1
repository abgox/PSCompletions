function handleCompletions($completions) {
    $tempList = @()

    $filter_input_arr = $PSCompletions.filter_input_arr

    # Example
    switch ($filter_input_arr[-1]) {
        'add' {
            $tempList += $PSCompletions.return_completion('abc', "Add a new item.")
        }
    }

    return $tempList + $completions
}
