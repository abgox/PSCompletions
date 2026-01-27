# Refer to: https://pscompletions.abgox.com/completion/hooks
function handleCompletions($completions) {
    $list = @()

    # $input_arr = $PSCompletions.input_arr
    $filter_input_arr = $PSCompletions.filter_input_arr # Exclude options parameters
    # $first_item = $filter_input_arr[0] # The first subcommand
    # $last_item = $filter_input_arr[-1] # The last subcommand

    if ($filter_input_arr) {
        return $completions
    }

    $manifests = Get-ChildItem bucket -Recurse -Filter *.json -ErrorAction Ignore

    foreach ($m in $manifests) {
        $list += $PSCompletions.return_completion($m.BaseName, $m.FullName)
    }

    return $list + $completions
}
