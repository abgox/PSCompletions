function Get-RecentCompletions {
    param(
        [string]$CompletionsDir
    )

    $guid = [guid]::NewGuid()
    $recentCompletions = git -c core.safecrlf=false log --since="1 day ago" --name-only --pretty=format:"$guid%n" -- 'completions/' |
    ForEach-Object {
        if ($_ -eq '') { return }
        if ($_ -eq $guid) {
            if ($current) {
                $current
            }
            $current = @()
        }
        else {
            $current += $_
        }
    } -End {
        if ($current) {
            $current
        }
    }
    $trackedChanges = git -c core.safecrlf=false diff --name-only HEAD -- 'completions/'
    $untrackedChanges = git -c core.safecrlf=false ls-files --others --exclude-standard -- 'completions/'
    $allChanges = @($recentCompletions) + @($trackedChanges) + @($untrackedChanges) |
    Where-Object { $_ -match '\.json$' -and (Test-Path $_) } |
    Sort-Object -Unique

    $completionList = @()
    foreach ($change in $allChanges) {
        if ($change -match '^completions/([^/]+)/') {
            $completionList += $Matches[1]
        }
    }
    return $completionList | Sort-Object -Unique
}
