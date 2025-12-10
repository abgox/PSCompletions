# Refer to: https://pscompletions.abgox.com/completion/hooks
function handleCompletions($completions) {
    $list = @()

    # $input_arr = $PSCompletions.input_arr
    $filter_input_arr = $PSCompletions.filter_input_arr # Without -*

    # switch ($filter_input_arr[-1]) {
    #     'add' {
    #         $list += $PSCompletions.return_completion('aaa', "Add aaa")
    #     }
    # }

    $list += $PSCompletions.return_completion('example', "It's from hooks.ps1")

    return $list + $completions
}
