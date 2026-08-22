function PSCompletions {
    try { Microsoft.PowerShell.Core\Set-StrictMode -Off } catch { }

    $arg = $args

    # Must live in the psm1 (module session state): Invoke-Expression can't reach module variables from the ScriptsToProcess scope
    function _replace {
        param ($data, $separator = '')
        $data = [string]::Join($separator, @($data))
        if ($data -notlike '*{{*') { return $data }
        $matches = [regex]::Matches($data, $PSCompletions.replace_pattern)
        foreach ($match in $matches) {
            $data = $data.Replace($match.Value, [string]::Join($separator, @(Invoke-Expression $match.Groups[1].Value)))
        }
        if ($data -match $PSCompletions.replace_pattern) { _replace $data }else { return $data }
    }
    function _get_library_changes {
        $json = $PSCompletions.get_raw_content($PSCompletions.path.change)
        if ($json) {
            try { return $PSCompletions.ConvertFrom_JsonAsHashtable($json) } catch { }
        }
        return $null
    }
    function _param_err {
        param($flag, $cmd, $err_info = $PSCompletions.info.$cmd.err.$flag)
        $err = if ($flag -eq 'min') { $PSCompletions.info.param_min }
        elseif ($flag -eq 'max') { $PSCompletions.info.param_max }
        else { $PSCompletions.info.param_err }
        $PSCompletions.write_with_color((_replace $err))
        if ($err_info) { $PSCompletions.write_with_color((_replace $err_info)) }
    }
    function _help {
        $PSCompletions.write_with_color((_replace $PSCompletions.info.description))
    }
    # Forward management commands to the psc CLI (platform-agnostic core); with -Json request structured output
    function _forward_psc {
        param([switch]$Json, [switch]$Quiet)
        $pscBinary = $PSCompletions.psc_binary()
        if (!$pscBinary) {
            $PSCompletions.write_with_color('[PSCompletions] psc binary missing.')
            return
        }
        $dataDir = [System.IO.Path]::GetDirectoryName($PSCompletions.path.data)
        # psc emits UTF-8, but PowerShell decodes native output via [Console]::OutputEncoding (GBK on Chinese systems); switch temporarily
        $oldEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
        try {
            $raw = & $pscBinary --data $dataDir $(if ($Json) { '--json' }) @($arg) 2>&1
            $exit = $LASTEXITCODE
        }
        finally {
            [Console]::OutputEncoding = $oldEncoding
        }
        $text = ($raw | ForEach-Object {
                if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { [string]$_ }
            }) -join "`n"
        # Structured mode: when the CLI emits JSON, return it as-is (per-item results carry their own ok/error)
        if ($Json -and $text.Trim()) {
            try { return ($text | ConvertFrom-Json) } catch { }
        }
        # Render binary errors uniformly in red and stop
        if ($exit -ne 0) {
            if ($text.Trim()) {
                $PSCompletions.write_with_color((_replace "<@Red>$($text.Trim())"))
            }
            return
        }
        if (-not $Json) {
            if (-not $Quiet) {
                $PSCompletions.write_with_color((_replace "<@Green>$($raw -join "`n")"))
            }
            return
        }
        try {
            return ($text | ConvertFrom-Json)
        }
        catch {
            return $raw
        }
    }
    # Render in the original show_list table format (Completion / Alias columns).
    function _render_list {
        param($rows)
        foreach ($row in $rows) {
            [pscustomobject]@{ Completion = $row.completion; Alias = $row.aliases }
        }
    }
    # Render info.<kind>.done; templates read $completion/$display/etc via dynamic scope.
    # $display overrides the name line (e.g. "git -> git1" for a rename); aliases read local data.alias.
    function _render_completion_done {
        param([string]$completion, [string]$kind, [string]$display = '')
        $completion_dir = [System.IO.Path]::Combine($PSCompletions.path.completions, $completion)
        $config = $null
        $json = $null
        $conflict_alias = @()
        if ($kind -ne 'rm') {
            $config = $PSCompletions.get_raw_content("$completion_dir/config.json") | ConvertFrom-Json
            $language = $PSCompletions.get_language($completion)
            $json = $PSCompletions.ConvertFrom_JsonAsHashtable($PSCompletions.get_raw_content("$completion_dir/language/$language.json"))
            foreach ($a in $PSCompletions.data.alias[$completion]) {
                if ($PSCompletions.data.aliasMap[$a] -and $PSCompletions.data.aliasMap[$a] -ne $completion) {
                    $conflict_alias += $a
                }
            }
        }
        $PSCompletions.write_with_color((_replace $PSCompletions.info.$kind.done))
    }
    $need_init = $true
    switch ($arg[0]) {
        'list' { _render_list (_forward_psc -Json); $need_init = $false }
        'add' {
            $targets = @()
            if ($arg -contains '--all') {
                $PSCompletions.write_with_color((_replace $PSCompletions.info.add.all_confirm))
                while (($PressKey = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')).VirtualKeyCode) {
                    # Ignore keys with any modifier (Alt/Ctrl/Shift bits of ControlKeyStates):
                    # only a bare key decides. NumLock/CapsLock/ScrollLock bits are excluded.
                    if (-not ($PressKey.ControlKeyState -band 0x1F)) {
                        if ($PressKey.VirtualKeyCode -eq 13) { $targets = @($PSCompletions.list) }
                        else { $PSCompletions.write_with_color((_replace $PSCompletions.info.confirm_cancel)) }
                        break
                    }
                }
            }
            else { $targets = @($arg[1..($arg.Count - 1)]) }
            if ($targets.Count) {
                $is_exist_before = @{}
                foreach ($t in $targets) { if ($t) { $is_exist_before[$t] = [System.IO.Directory]::Exists([System.IO.Path]::Combine($PSCompletions.path.completions, $t)) } }
                if ($arg -contains '--all') {
                    $PSCompletions.write_with_color("`n" + (_replace $PSCompletions.info.add.waiting))
                }
                $result = _forward_psc -Json
                if ($null -ne $result) {
                    $PSCompletions.init_data()
                    foreach ($r in @($result)) {
                        if ($r.ok) {
                            _render_completion_done $r.completion $(if ($is_exist_before[$r.completion]) { 'update' } else { 'add' })
                        }
                        else {
                            $PSCompletions.write_with_color((_replace "<@Red>$($r.completion): $($r.error)"))
                        }
                    }
                }
            }
            $need_init = $false
        }
        'rm' {
            $targets = @()
            if ($arg -contains '--all') {
                $PSCompletions.write_with_color((_replace $PSCompletions.info.rm.all_confirm))
                while (($PressKey = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')).VirtualKeyCode) {
                    # Ignore keys with any modifier (Alt/Ctrl/Shift bits of ControlKeyStates):
                    # only a bare key decides. NumLock/CapsLock/ScrollLock bits are excluded.
                    if (-not ($PressKey.ControlKeyState -band 0x1F)) {
                        if ($PressKey.VirtualKeyCode -eq 13) { $targets = @($PSCompletions.data.list) }
                        else { $PSCompletions.write_with_color((_replace $PSCompletions.info.confirm_cancel)) }
                        break
                    }
                }
            }
            else { $targets = @($arg[1..($arg.Count - 1)]) }
            if ($targets.Count) {
                $result = _forward_psc -Json
                if ($null -ne $result) {
                    $PSCompletions.init_data()
                    foreach ($r in @($result)) {
                        if ($r.ok) {
                            _render_completion_done $r.completion 'rm'
                        }
                        else {
                            $PSCompletions.write_with_color((_replace "<@Red>$($r.completion): $($r.error)"))
                        }
                    }
                }
            }
            $need_init = $false
        }
        'update' {
            # Plain `psc update` (no targets) = live check; the CLI refreshes change.json.
            # --all / --old / named update: the CLI returns per-completion JSON results.
            $isNoArg = $arg.Count -eq 1
            if ($isNoArg) {
                # no-arg live check: render change.json, else a one-line reply.
                # update/renamed persist until `psc update --old`; added/removed are one-shot.
                _forward_psc -Quiet | Out-Null
                $changes = _get_library_changes
                $upd = @($changes.update)
                $add = @($changes.added)
                $rm = @($changes.removed)
                $renamed = @($changes.renamed)
                if ($upd -or $add -or $rm -or $renamed) {
                    $PSCompletions.update = $upd
                    $PSCompletions.added = $add
                    $PSCompletions.removed = $rm
                    $PSCompletions.renamed = $renamed
                    $PSCompletions.write_with_color((_replace $PSCompletions.info.update_info))
                    $changes.added = @()
                    $changes.removed = @()
                    try {
                        [System.IO.File]::WriteAllText(
                            $PSCompletions.path.change,
                            ($changes | ConvertTo-Json -Depth 6 -Compress),
                            [System.Text.Encoding]::UTF8)
                    }
                    catch { }
                }
                else {
                    $PSCompletions.write_with_color((_replace $PSCompletions.info.update.no))
                }
                # This command already rendered the library changes; skip them in the pending tail.
                $PSCompletions.pending_skip_library = $true
            }
            else {
                # --all / --old / named update: the CLI returns per-completion JSON results.
                $result = _forward_psc -Json
                if ($null -ne $result) {
                    $PSCompletions.init_data()
                    $anyOk = $false
                    $migratedRenamed = @()
                    foreach ($r in @($result)) {
                        if ($r.ok) {
                            $anyOk = $true
                            if ($r.renamed_from) {
                                $migratedRenamed += , @($r.renamed_from, $r.completion)
                                # Migrated rename: display "old -> new", resolve config/alias from the real name.
                                _render_completion_done $r.completion 'update' "$($r.renamed_from) -> $($r.completion)"
                            }
                            else {
                                _render_completion_done $r.completion 'update'
                            }
                        }
                        else {
                            $PSCompletions.write_with_color((_replace "<@Red>$($r.completion): $($r.error)"))
                        }
                    }
                    if (-not $anyOk -and -not @($result).Count) {
                        $PSCompletions.write_with_color((_replace $PSCompletions.info.update.no))
                    }
                    # Consume only the renames actually migrated this run (from the CLI results);
                    # unmigrated renames (e.g. a different renamed completion) stay for later prompts.
                    if ($migratedRenamed.Count) {
                        $changes = _get_library_changes
                        if ($changes) {
                            $changes.renamed = @(@($changes.renamed) | Where-Object {
                                    $pair = @($_)
                                    $hit = $false
                                    foreach ($m in $migratedRenamed) {
                                        if ($pair[0] -eq $m[0] -and $pair[1] -eq $m[1]) { $hit = $true; break }
                                    }
                                    -not $hit
                                })
                            try {
                                [System.IO.File]::WriteAllText(
                                    $PSCompletions.path.change,
                                    ($changes | ConvertTo-Json -Depth 6 -Compress),
                                    [System.Text.Encoding]::UTF8)
                            }
                            catch { }
                        }
                    }
                }
            }
            $need_init = $false
        }
        'info' { _forward_psc -Json | ForEach-Object { [pscustomobject]@{ Name = $_.name; Alias = $_.alias; Url = $_.url; Description = $_.description; Path = Convert-Path $_.path; Update = $_.update; Updated = if ($null -ne $_.updated) { [DateTimeOffset]::FromUnixTimeSeconds([int64]$_.updated).LocalDateTime } } }; $need_init = $false }
        'alias' {
            # `alias add` pre-check: an alias colliding with a real command is rejected before forwarding
            $alias_conflict = $false
            if ($arg[1] -eq 'add' -and $arg.Count -ge 4) {
                foreach ($a in $arg[3..($arg.Count - 1)]) {
                    if (Get-Command $a -ErrorAction Ignore) {
                        $alias = $a
                        $PSCompletions.write_with_color((_replace $PSCompletions.info.alias.add.err.cmd_exist))
                        $alias_conflict = $true
                    }
                }
            }
            if (-not $alias_conflict) {
                if ($arg.Count -eq 1) {
                    # No args = list all trigger aliases, wrapped as objects like list
                    _forward_psc -Json | ForEach-Object { [pscustomobject]@{ Completion = $_.completion; Alias = $_.aliases } }
                }
                else { _forward_psc }
            }
        }
        'config' {
            # Grouped syntax: config | config <group> | config <group> <key> | config <group> <key> <value>
            if ($arg -contains '--reset') {
                _forward_psc
                if ($LASTEXITCODE -eq 0 -and $arg[1] -eq 'menu' -and $arg[2] -eq 'trigger_key') {
                    $PSCompletions.init_data()
                    $PSCompletions.handle_completion()
                    $need_init = $false
                }
            }
            elseif ($arg.Count -le 2) { _forward_psc -Json | ForEach-Object { [pscustomobject]@{ Key = $_.key; Value = $_.value } } }
            elseif ($arg.Count -eq 3) { _forward_psc -Json | ForEach-Object { $_.value } }
            else {
                # trigger_key host side-effect: rebind PSReadLine first, persist only on success
                if ($arg[1] -eq 'menu' -and $arg[2] -eq 'trigger_key') {
                    $oldKey = $PSCompletions.config.trigger_key
                    try {
                        Remove-PSReadLineKeyHandler $oldKey
                        Set-PSReadLineKeyHandler -Key $arg[3] -ScriptBlock $PSCompletions.menu.module_completion_menu_script
                    }
                    catch {
                        # Rebind failed: restore the removed old trigger key to avoid "old key dead and new key not active"
                        try {
                            Set-PSReadLineKeyHandler -Key $oldKey -ScriptBlock $PSCompletions.menu.module_completion_menu_script
                        }
                        catch { }
                        _param_err 'err' 'trigger_key' $PSCompletions.info.menu.config.err.trigger_key
                        $need_init = $false
                        break
                    }
                }
                _forward_psc
                if ($LASTEXITCODE -eq 0 -and $arg[1] -eq 'menu' -and $arg[2] -eq 'trigger_key') {
                    $PSCompletions.config.trigger_key = $arg[3]
                    $PSCompletions.handle_completion()
                }
            }
        }
        'completion' {
            if ($arg -contains '--reset') { _forward_psc }
            elseif ($arg.Count -eq 3) { (_forward_psc -Json) | ForEach-Object { $_.value } }
            elseif ($arg.Count -le 2) {
                # No args / <name>: list special config, wrapped as objects
                _forward_psc -Json | ForEach-Object { [pscustomobject]@{ Completion = $_.completion; Config = $_.config } }
            }
            else { _forward_psc }
        }
        '--reset' {
            $need_init = $false
            # After interactive confirmation, clear the module's data directory and re-initialize
            $PSCompletions.write_with_color((_replace $PSCompletions.info.reset.init_confirm))
            while (($PressKey = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')).VirtualKeyCode) {
                # Ignore keys with any modifier (Alt/Ctrl/Shift bits of ControlKeyStates):
                # only a bare key decides. NumLock/CapsLock/ScrollLock bits are excluded.
                if (-not ($PressKey.ControlKeyState -band 0x1F)) {
                    if ($PressKey.VirtualKeyCode -eq 13) {
                        Get-ChildItem ($PSCompletions.path.root + '/data') | ForEach-Object { Remove-Item $_.FullName -Force -Recurse }
                        $PSCompletions.write_with_color((_replace $PSCompletions.info.reset.init_done))
                        $PSCompletions.ensure_dir($PSCompletions.path.completions)
                        $PSCompletions.init_data()
                    }
                    else {
                        $PSCompletions.write_with_color((_replace $PSCompletions.info.confirm_cancel))
                    }
                    break
                }
            }
        }
        default {
            $need_init = $false
            _help
        }
    }
    if ($need_init) { $PSCompletions.init_data() }
    # Append pending module/library notifications after the command's own output.
    $PSCompletions.render_pending()
}

Export-ModuleMember -Function PSCompletions
