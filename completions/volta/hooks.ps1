function handleCompletions($completions) {
    $tempList = @()

    $voltaBinDir = Split-Path (Get-Command volta).Source -Parent
    $toolsDir = "$(Split-Path $voltaBinDir -Parent)\tools\image"
    $list = @("node", "npm", "pnpm", "yarn")

    $filter_input_arr = $PSCompletions.filter_input_arr

    switch ($filter_input_arr[-1]) {
        'pin' {
            foreach ($l in $list) {
                $versionList = Get-ChildItem "$toolsDir\$l" -Directory
                foreach ($v in $versionList) {
                    $tempList += $PSCompletions.return_completion("$l@$($v.BaseName)", "pin - $l@$($v.BaseName)")
                }
            }
        }
    }
    return $tempList + $completions
}
