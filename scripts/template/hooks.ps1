# Refer to: https://pscompletions.abgox.com/completion/hooks
function handleCompletions($completions) {
    $list = @()

    $input_arr = $PSCompletions.input_arr
    $filter_input_arr = $PSCompletions.filter_input_arr # Exclude options parameters
    $first_item = $filter_input_arr[0] # The first subcommand
    $last_item = $filter_input_arr[-1] # The last subcommand

    # switch ($first_item) {
    #     'add' {
    #         if ('aaa' -notin $input_arr) {
    #             $list += $PSCompletions.return_completion('aaa', "Add aaa")
    #         }
    #     }
    # }

    # switch ($last_item) {
    #     'add' {
    #         $list += $PSCompletions.return_completion('bbb', "Add bbb")
    #     }
    # }

    # $list += $PSCompletions.return_completion('example', "It's from hooks.ps1")

    return $list + $completions
}
