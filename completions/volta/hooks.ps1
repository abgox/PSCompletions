function handleCompletions($completions) {
    if (!(Get-Command volta -ErrorAction SilentlyContinue)) {
        return $completions
    }

    $list = @()

    $voltaBinDir = Split-Path (Get-Command volta).Source -Parent
    $toolsDir = "$voltaBinDir\tools\image"
    if (!(Test-Path $toolsDir)) {
        $toolsDir = "$(Split-Path $voltaBinDir -Parent)\tools\image"
    }
    if (!(Test-Path $toolsDir)) {
        $toolsDir = "$($env:LocalAppData)\Volta\tools\image"
    }
    if (!(Test-Path $toolsDir)) {
        return $completions
    }

    $tool_list = @("node", "npm", "pnpm", "yarn")

    $input_arr = $PSCompletions.input_arr
    $filter_input_arr = $PSCompletions.filter_input_arr # Exclude options parameters
    $first_item = $filter_input_arr[0] # The first subcommand
    $last_item = $filter_input_arr[-1] # The last subcommand

    switch ($last_item) {
        'pin' {
            foreach ($l in $tool_list) {
                $versionList = Get-ChildItem "$toolsDir\$l" -Directory
                foreach ($v in $versionList) {
                    $list += $PSCompletions.return_completion("$l@$($v.BaseName)", "pin - $l@$($v.BaseName)")
                }
            }
        }
        'uninstall' {
            foreach ($l in $tool_list) {
                $versionList = Get-ChildItem "$toolsDir\$l" -Directory
                foreach ($v in $versionList) {
                    $list += $PSCompletions.return_completion("$l@$($v.BaseName)", "uninstall - $l@$($v.BaseName)")
                }
            }

            $packages = Get-ChildItem "$toolsDir\packages" -Directory
            foreach ($p in $packages) {
                $name = $p.BaseName
                $list += $PSCompletions.return_completion($name, "uninstall - $name")
            }
        }
        'which' {
            foreach ($l in $tool_list) {
                $list += $PSCompletions.return_completion("$l", "which - $l")
            }
        }
    }
    return $list + $completions
}
