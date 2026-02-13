# Refer to: https://pscompletions.abgox.com/completion/hooks
function handleCompletions($completions) {
    $list = @()

    $input_arr = $PSCompletions.input_arr
    $filter_input_arr = $PSCompletions.filter_input_arr # Exclude options parameters
    $first_item = $filter_input_arr[0] # The first subcommand
    $last_item = $filter_input_arr[-1] # The last subcommand

    function return_pkg_list {
        $res = @()
        $info = ya pkg list
        foreach ($i in $info) {
            $line = $i.Trim()
            if ($line -in @('Plugins:', 'Flavors:')) {
                continue
            }
            $line | Select-String -Pattern '([^/]+/[^/]+)\s+' | ForEach-Object {
                $_.Matches.Groups[1].Value
            }
        }
    }

    switch ($first_item) {
        'pkg' {
            if ($filter_input_arr[1] -in 'delete', 'upgrade') {
                $list += return_pkg_list | ForEach-Object {
                    if ($_ -notin $filter_input_arr) {
                        $PSCompletions.return_completion($_)
                    }
                }
            }
        }
    }

    return $list + $completions
}
