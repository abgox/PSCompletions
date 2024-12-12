function handleCompletions($completions) {
    $tempList = @()

    # Example
    switch ($PSCompletions.filter_input_arr[-1]) {
        'add' {
            $tempList += $PSCompletions.return_completion('abc', "Add a new item.")
        }
    }

    return $tempList + $completions
}
