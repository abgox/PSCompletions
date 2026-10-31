function PSCompletions {
    try { Microsoft.PowerShell.Core\Set-StrictMode -Off } catch { }

    $PSCompletions.initialize()
    if (-not $PSCompletions.binary_ok) { return }

    $arg = $args

    # `--json` anywhere in the invocation is the machine contract: hand it to the engine as it is and print what it says — no rendering, no color, and no prompt (design/json.md §7).
    # With no command word it is the **root** response (§5), not the info page; the shell bridges do the same, so a caller gets parseable JSON from every host.
    if ($arg -contains '--json') {
        $pscBinary = $PSCompletions.psc_binary()
        if ($pscBinary) {
            $oldEncoding = [Console]::OutputEncoding
            [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
            try { & $pscBinary --data $PSCompletions.path.dir.data @($arg) }
            finally { [Console]::OutputEncoding = $oldEncoding }
        }
        return
    }

    # Must live in the psm1 (module session state): the renderer is pure, but the call must resolve here so future host-specific lookups keep working.
    function _replace {
        param ($data, $ctx = @{}, $separator = '')
        $PSCompletions.render_engine($data, $ctx, $separator)
    }
    function _get_library_changes {
        $json = $PSCompletions.get_raw_content($PSCompletions.path.file.change)
        if ($json) {
            try { return $PSCompletions.ConvertFrom_JsonAsHashtable($json) } catch { }
        }
        return $null
    }
    function _param_err {
        param($flag, $cmd, $err_info = $PSCompletions.info.$cmd.err.$flag)
        $err = if ($flag -eq 'min') { $PSCompletions.info.too_few_params }
        elseif ($flag -eq 'max') { $PSCompletions.info.too_many_params }
        else { $PSCompletions.info.param_err }
        $PSCompletions.write_with_color((_replace $err))
        if ($err_info) { $PSCompletions.write_with_color((_replace $err_info @{Rejected = if ($arg.Count -gt 3) { [string]$arg[3] } else { '' } })) }
    }
    function _help {
        $PSCompletions.write_with_color((_replace $PSCompletions.info.description @{Version = [string]$PSCompletions.version }))
    }
    # Forward management commands to the psc CLI (platform-agnostic core); with -Json request structured output, with -Plain print a read uncolored (a status message takes green).
    function _forward_psc {
        param([switch]$Json, [switch]$Quiet, [switch]$Plain)
        $pscBinary = $PSCompletions.psc_binary()
        if (!$pscBinary) {
            $PSCompletions.write_with_color('[PSCompletions] psc binary missing.')
            return
        }
        $dataDir = $PSCompletions.path.dir.data
        # The engine never prompts: it refuses a destructive operation unless it is authorised (design/json.md §7).
        # The host is the one that asks the human, so it supplies the authorisation here — the single place the module calls the engine.
        # `rm --all` has already been confirmed by the case that called this; a group `--reset` is not destructive enough to ask about, so the host simply says yes.
        $destructive = ($arg -contains '--reset') -or (($arg | Select-Object -First 1) -eq 'rm' -and ($arg -contains '--all'))
        $authorised = if ($destructive) { @('--yes') } else { @() }
        # psc emits UTF-8, but PowerShell decodes native output via [Console]::OutputEncoding (GBK on Chinese systems); switch temporarily
        $oldEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
        try {
            $raw = & $pscBinary --data $dataDir $(if ($Json) { '--json' }) @($arg) @($authorised) 2>&1
            $exit = $LASTEXITCODE
        }
        finally {
            [Console]::OutputEncoding = $oldEncoding
        }
        $text = ($raw | ForEach-Object {
                if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { [string]$_ }
            }) -join "`n"
        # Render binary errors uniformly in red and stop — check exit before Json
        if ($exit -ne 0) {
            if ($Json) {
                # A partial failure (`ok:false` per item) is not a whole-command error: hand the payload back so the caller renders the items.
                # Only an envelope carrying an `error` is shown as one red line.
                try {
                    $parsed = $text | ConvertFrom-Json
                    if ($null -ne $parsed.data) { return $parsed.data }
                    if ($parsed.error.message) {
                        $PSCompletions.write_with_color((_replace "<@Red>$($parsed.error.message)"))
                        return
                    }
                }
                catch { }
            }
            if ($text.Trim()) {
                $PSCompletions.write_with_color((_replace "<@Red>$($text.Trim())"))
            }
            return
        }
        if ($Json -and $text.Trim()) {
            try {
                # The envelope's payload: `data` is what this command's caller renders.
                return ($text | ConvertFrom-Json).data
            }
            catch {
                return @{ ok = $false; error = $_.Exception.Message }
            }
        }
        if (-not $Json) {
            if (-not $Quiet) {
                # A data read prints the CLI's text as it is; a status message is a message and takes green.
                # The failure path above stays red either way.
                if ($Plain) { $raw -join "`n" }
                else { $PSCompletions.write_with_color((_replace "<@Green>$($raw -join "`n")")) }
            }
            return
        }
        try {
            return $text | ConvertFrom-Json
        }
        catch {
            if ($Json) {
                return @{ ok = $false; error = $_.Exception.Message }
            }
            return $raw
        }
    }
    # Build the add/update done-template context: trigger aliases plus the manifest config rows (with stored current values) for [Special Configuration].
    function _done_ctx {
        param([string]$completion, [string]$display = '')
        $alias = @($PSCompletions.data.alias[$completion])
        if (-not $alias) { $alias = @($completion) }
        $rows = @()
        $completion_dir = [System.IO.Path]::Combine($PSCompletions.path.dir.completions, $completion)
        try { $cfgjson = $PSCompletions.get_raw_content("$completion_dir/config.json") | ConvertFrom-Json } catch { $cfgjson = $null }
        try {
            $clang = $PSCompletions.get_language($completion)
            $man = $PSCompletions.ConvertFrom_JsonAsHashtable($PSCompletions.get_raw_content("$completion_dir/language/$clang.json"))
        }
        catch { $man = $null }
        if ($cfgjson -and $null -ne $cfgjson.hooks) {
            $rows += @{ Name = 'enable_hooks'; Value = [int][bool]$cfgjson.hooks; Tip = (($PSCompletions.info.completion.enable_hooks.tip) -join "`n") }
        }
        foreach ($item in @($man.config)) {
            if ($item.name) { $rows += @{ Name = [string]$item.name; Value = $item.value; Tip = ($item.tip -join "`n") } }
        }
        $stored = @{}
        if ($PSCompletions.config.completion) { $stored = $PSCompletions.config.completion[$completion] }
        foreach ($row in $rows) {
            $cur = $null
            if ($stored) {
                if ($stored -is [hashtable] -and $stored.ContainsKey($row.name)) { $cur = $stored[$row.name] }
                elseif ($null -ne $stored.PSObject.Properties[$row.name]) { $cur = $stored.PSObject.Properties[$row.name].Value }
            }
            if ($null -ne $cur) { $row.Current = $cur }
        }
        @{ Completion = $completion; Display = $display; Alias = $alias; Configs = $rows }
    }
    # Render info.<kind>.done; templates read $completion/$display/etc via dynamic scope.
    # $display overrides the name line (e.g. "git -> git1" for a rename); aliases read local data.alias.
    function _render_completion_done {
        param([string]$completion, [string]$kind, [string]$display = '')
        if ($kind -in @('add', 'update')) {
            # Each of these renders a multi-line block, so consecutive blocks are separated by a blank line — the same gap the templates put between their own repeated items (design/templates.md).
            # `rm`'s done is one line per completion and stays tight.
            if ($script:_done_block) { $PSCompletions.write_with_color('') }
            $PSCompletions.write_with_color((_replace $PSCompletions.info.$kind.done (_done_ctx $completion $display)))
            $script:_done_block = $true
            return
        }
        $PSCompletions.write_with_color((_replace $PSCompletions.info.$kind.done @{ Completion = $completion }))
    }
    $need_init = $true
    switch ($arg[0]) {
        'list' { _forward_psc -Plain; $need_init = $false }
        'add' {
            $targets = @($arg[1..($arg.Count - 1)])
            if ($targets.Count) {
                # The payload names its collection; each item carries its name and a stable code.
                $rows = @((_forward_psc -Json).completions)
                if ($rows.Count) {
                    $PSCompletions.init_data()
                    $script:_done_block = $false
                    foreach ($r in $rows) {
                        if ($r.ok) {
                            _render_completion_done $r.name 'add'
                        }
                        else {
                            $PSCompletions.write_with_color((_replace "<@Red>$(if ($r.name) { "$($r.name): " })$($r.error.message)"))
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
                    # only a bare key decides.
                    # NumLock/CapsLock/ScrollLock bits are excluded.
                    if (-not ($PressKey.ControlKeyState -band 0x1F)) {
                        if ($PressKey.VirtualKeyCode -eq 13) { $targets = @($PSCompletions.data.list) }
                        else { $PSCompletions.write_with_color((_replace $PSCompletions.info.confirm_cancel)) }
                        break
                    }
                }
            }
            else { $targets = @($arg[1..($arg.Count - 1)]) }
            if ($targets.Count) {
                # The payload names its collection; each item carries its name and a stable code.
                $rows = @((_forward_psc -Json).completions)
                if ($rows.Count) {
                    $PSCompletions.init_data()
                    foreach ($r in $rows) {
                        if ($r.ok) {
                            _render_completion_done $r.name 'rm'
                        }
                        else {
                            $PSCompletions.write_with_color((_replace "<@Red>$(if ($r.name) { "$($r.name): " })$($r.error.message)"))
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
                    $PSCompletions.write_with_color((_replace $PSCompletions.info.update_info @{ Added = @($add); Removed = @($rm); Update = @($upd); Renamed = @($renamed) }))
                    $changes.added = @()
                    $changes.removed = @()
                    try {
                        [System.IO.File]::WriteAllText(
                            $PSCompletions.path.file.change,
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
                # --all / --old / named update: the payload names its per-completion collection.
                $rows = @((_forward_psc -Json).completions)
                if (-not $rows.Count) {
                    $PSCompletions.write_with_color((_replace $PSCompletions.info.update.no))
                }
                else {
                    $PSCompletions.init_data()
                    $anyOk = $false
                    $script:_done_block = $false
                    $migratedRenamed = @()
                    foreach ($r in $rows) {
                        if ($r.ok) {
                            $anyOk = $true
                            if ($r.renamed_from) {
                                $migratedRenamed += , @($r.renamed_from, $r.name)
                                # Migrated rename: display "old -> new", resolve config/alias from the real name.
                                _render_completion_done $r.name 'update' "$($r.renamed_from) -> $($r.name)"
                            }
                            else {
                                _render_completion_done $r.name 'update'
                            }
                        }
                        else {
                            $PSCompletions.write_with_color((_replace "<@Red>$(if ($r.name) { "$($r.name): " })$($r.error.message)"))
                        }
                    }
                    if (-not $anyOk -and -not $rows.Count) {
                        $PSCompletions.write_with_color((_replace $PSCompletions.info.update.no))
                    }
                    # Consume only the renames actually migrated this run (from the CLI results); unmigrated renames (e.g. a different renamed completion) stay for later prompts.
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
                                    $PSCompletions.path.file.change,
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
        'info' {
            # A read is the CLI's text, uncolored — the same thing the POSIX bridges print.
            # Data leaves through `--json`; the human view is one shape everywhere (bridge.md §7).
            _forward_psc -Plain
            $need_init = $false
        }
        'alias' {
            # A read is the CLI's text; `add` / `rm` / `--reset` stay on the action path so the init refresh and the pending tail still run.
            if ($arg.Count -eq 1) { _forward_psc -Plain; $need_init = $false }
            else { _forward_psc }
        }
        'config' {
            # Grouped syntax: config | config <group> | config <group> <key> | config <group> <key> <value>
            if ($arg -contains '--reset') {
                _forward_psc
                if ($LASTEXITCODE -eq 0 -and $arg[1] -eq 'menu' -and $arg[2] -eq 'trigger_key') {
                    $PSCompletions.init_data()
                    Set-PSReadLineKeyHandler -Key $PSCompletions.config.trigger_key -ScriptBlock $PSCompletions.menu.script -BriefDescription 'PSCompletionsMenuComplete' -Description 'Open the completion menu provided by PSCompletions.'
                    $need_init = $false
                }
            }
            elseif ($arg.Count -le 3) {
                # Every read is the CLI's text: a group listing, or the bare value of one key.
                _forward_psc -Plain
                $need_init = $false
            }
            else {
                # trigger_key host side-effect: rebind PSReadLine first, persist only on success
                if ($arg[1] -eq 'menu' -and $arg[2] -eq 'trigger_key') {
                    $oldKey = $PSCompletions.config.trigger_key
                    try {
                        Remove-PSReadLineKeyHandler $oldKey
                        Set-PSReadLineKeyHandler -Key $arg[3] -ScriptBlock $PSCompletions.menu.script -BriefDescription 'PSCompletionsMenuComplete' -Description 'Open the completion menu provided by PSCompletions.'
                    }
                    catch {
                        # Rebind failed: restore the removed old trigger key to avoid "old key dead and new key not active"
                        try {
                            Set-PSReadLineKeyHandler -Key $oldKey -ScriptBlock $PSCompletions.menu.script -BriefDescription 'PSCompletionsMenuComplete' -Description 'Open the completion menu provided by PSCompletions.'
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
                    Set-PSReadLineKeyHandler -Key $arg[3] -ScriptBlock $PSCompletions.menu.script -BriefDescription 'PSCompletionsMenuComplete' -Description 'Open the completion menu provided by PSCompletions.'
                }
            }
        }
        'completion' {
            # Reads print the CLI's text; `--reset` and a set stay on the action path.
            if ($arg -contains '--reset' -or $arg.Count -gt 3) { _forward_psc }
            else { _forward_psc -Plain; $need_init = $false }
        }
        '--self-update' {
            # A root-level flag, not a command: the engine detects how this copy was installed and says what updates it.
            # `-Plain` because the text is a read, like `info`.
            _forward_psc -Plain
            $need_init = $false
            # The engine just reported the module state; the pending tail must not repeat it.
            $PSCompletions.pending_skip_module = $true
        }
        '--reset' {
            $need_init = $false
            # After interactive confirmation, clear the module's data directory and re-initialize
            $PSCompletions.write_with_color((_replace $PSCompletions.info.reset.init_confirm))
            while (($PressKey = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')).VirtualKeyCode) {
                # Ignore keys with any modifier (Alt/Ctrl/Shift bits of ControlKeyStates):
                # only a bare key decides.
                # NumLock/CapsLock/ScrollLock bits are excluded.
                if (-not ($PressKey.ControlKeyState -band 0x1F)) {
                    if ($PressKey.VirtualKeyCode -eq 13) {
                        if ([System.IO.Directory]::Exists($PSCompletions.path.dir.data)) {
                            Get-ChildItem -LiteralPath $PSCompletions.path.dir.data -Force | ForEach-Object { Remove-Item $_.FullName -Force -Recurse }
                        }
                        $PSCompletions.write_with_color((_replace $PSCompletions.info.reset.init_done))
                        $PSCompletions.ensure_dir($PSCompletions.path.dir.completions)
                        $seedTarget = [System.IO.Path]::Combine($PSCompletions.path.dir.completions, 'psc')
                        foreach ($seed in @(
                                [System.IO.Path]::Combine($PSCompletions.path.dir.root, 'completions', 'psc'),
                                [System.IO.Path]::Combine((Split-Path (Split-Path $PSCompletions.path.dir.root -Parent) -Parent), 'completions', 'psc')
                            )) {
                            if ([System.IO.File]::Exists([System.IO.Path]::Combine($seed, 'config.json')) -and [System.IO.File]::Exists([System.IO.Path]::Combine($seed, 'language', 'en-US.json'))) {
                                Copy-Item -LiteralPath $seed -Destination $seedTarget -Recurse -Force
                                break
                            }
                        }
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

function psc { PSCompletions @args }

Export-ModuleMember -Function PSCompletions, psc
