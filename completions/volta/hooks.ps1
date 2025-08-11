function handleCompletions($completions) {
    $tempList = @()

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
        'uninstall' {
            foreach ($l in $list) {
                $versionList = Get-ChildItem "$toolsDir\$l" -Directory
                foreach ($v in $versionList) {
                    $tempList += $PSCompletions.return_completion("$l@$($v.BaseName)", "uninstall - $l@$($v.BaseName)")
                }
            }

            $packages = Get-ChildItem "$toolsDir\packages" -Directory
            foreach ($p in $packages) {
                $name = $p.BaseName
                $tempList += $PSCompletions.return_completion($name, "uninstall - $name")
            }
        }
        'which' {
            foreach ($l in $list) {
                $tempList += $PSCompletions.return_completion("$l", "which - $l")
            }
        }
    }
    return $tempList + $completions
}
