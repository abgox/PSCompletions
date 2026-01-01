# Refer to: https://pscompletions.abgox.com/completion/hooks
function handleCompletions($completions) {
    if (!(Get-Command zoxide -ErrorAction SilentlyContinue)) {
        return $completions
    }

    $list = @()

    # $input_arr = $PSCompletions.input_arr
    $filter_input_arr = $PSCompletions.filter_input_arr # Without -*

    switch ($filter_input_arr[0]) {
        'remove' {
            zoxide query --list | ForEach-Object {
                if ($_ -notin $filter_input_arr) {
                    $list += $PSCompletions.return_completion($_)
                }
            }
        }
    }

    return $list + $completions
}
