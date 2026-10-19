#!/usr/bin/env pwsh
#Requires -Version 7.6.5

<#
.SYNOPSIS
    Comprehensive validation for completion definitions (schema, config, hooks, and compare-json rules).
.DESCRIPTION
    For each completion, validates:
      - JSON Schema of every language/*.json (completion-manifest schema)
      - config.json (schema + language<->files consistency + hooks flag + alias extensions)
      - hooks.lua (existence/non-empty check, if present)
      - compare-json.ps1 -Json (all design/usage/structure/translation rules)
    Emits a structured result object. With -OutFile, writes a Markdown report in the given -Lang.
.EXAMPLE
    ./scripts/validate-completion.ps1 git cargo
    ./scripts/validate-completion.ps1 -All -Lang zh-CN -OutFile result-zh.md
#>

param(
    [Parameter(Position = 0, ValueFromRemainingArguments)]
    [string[]]$CompletionList,
    [switch]$All,
    # Report wording.
    # Empty (default) follows the machine locale: Chinese for zh* cultures, English otherwise.
    # check-completion.ps1 always passes en-US explicitly so the PR comment is deterministic on any runner locale.
    [string]$Lang = '',
    [string]$OutFile,
    # Dead psc.on targets, as reported by check-hook-targets.ps1 -Json (objects with completion/target/option/reason).
    # A dead target never fires, so those completions count as failed, and the report shows an inline CAUTION inside their section.
    [array]$HookTargetDetails = @(),
    # Completions whose config.json id differs from the base checkout: changing a stable id breaks rename detection, so those completions count as failed, with an inline CAUTION inside their section.
    [string[]]$IdChanged = @(),
    # Completion -> base version, for completions whose version baseline changed in this PR (both sides non-empty, values differ).
    # Rendered as old -> new on the baseline line; informational only, never a failure.
    [System.Collections.Hashtable]$VersionChanged = @{},
    # completion -> '`psc.run` / `psc.run_batch`' for hooks.lua files using those APIs.
    # Shown as an inline WARNING inside their section; advisory only, never counts as a failure.
    [System.Collections.Hashtable]$RunUsage = @{},
    # Skip the ## title: check-completion.ps1 writes its own title and splices this report in as the body.
    [switch]$NoTitle,
    # Machine-readable summary for check-completion.ps1: one object per completion (name/hasIssues/hasHooks/counts/version), as JSON on stdout.
    # Full section lines live only in the Markdown path above, so rendering stays in one place.
    # Human-readable $results stdout is suppressed here.
    [switch]$Json
)

Set-StrictMode -Off

if ([string]::IsNullOrEmpty($Lang)) {
    $Lang = if ($PSCulture -like 'zh*') { 'zh-CN' } else { 'en-US' }
}
if ($Lang -notin @('en-US', 'zh-CN')) { throw "Lang must be 'en-US' or 'zh-CN'." }

$root = Split-Path -Parent $PSScriptRoot
$completionsDir = Join-Path $root 'completions'
$manifestSchema = Join-Path $root 'schema/completion-manifest.en-US.json'
$configSchema = Join-Path $root 'schema/completion-config.en-US.json'

# A completion with dozens of schema errors (a mistyped `next`, a duplicated key) must not bury the other categories: each section shows at most this many lines, then one line saying how many are left.
# The counts stay in the summary table.
$MaxItemsPerSection = 10

if ($All) {
    $CompletionList = @(Get-ChildItem -LiteralPath $completionsDir -Directory | ForEach-Object { $_.Name })
}

$L = @{
    'en-US' = @{
        title                  = 'Completion Validation'
        secSchema              = 'Schema'
        secConfig              = 'Config'
        secHooks               = 'Hooks'
        secCompare             = 'Compare'
        version                = 'CLI version baseline'
        versionChanged         = 'CLI version baseline changed'
        versionOld             = 'old'
        versionNew             = 'new'
        cat_missingInTarget    = 'Missing items'
        cat_extraInTarget      = 'Extra items'
        cat_typeMismatch       = 'Type mismatch'
        cat_semanticMismatch   = 'Semantic mismatch'
        cat_valueDiff          = 'Value difference'
        cat_duplicateItems     = 'Duplicate items'
        cat_untranslated       = 'Untranslated content'
        cat_meaninglessUsage   = 'Meaningless usage line'
        cat_missingUsage       = 'Missing usage line'
        cat_usageOrder         = 'Usage order'
        cat_usageTooSimple     = 'Usage too simple'
        cat_usageSeparator     = 'Usage separator'
        cat_duplicateOptions   = 'Global option duplicates'
        cat_optionMissingNext  = 'Option with value missing next'
        cat_forbiddenEmptyNext = 'Command with forbidden empty next'
        cat_usageRootPrefix    = 'Usage root prefix'
        cat_rate               = 'Translation rate'
        cfg_missingLanguage    = 'config.json is missing the "language" array'
        cfg_missingVersion     = 'config.json is missing "version" (the CLI version this completion was written and checked against)'
        cfg_missingFile        = '{0} is missing (required)'
        cfg_langNoFile         = 'config.language has "{0}" but language/{0}.json does not exist'
        cfg_fileNoLang         = 'language/{0}.json exists but is not declared in config.language'
        cfg_hooksFlagNoFile    = 'config.hooks=true/false but hooks.lua does not exist'
        cfg_hooksFileNoFlag    = 'hooks.lua exists but config.hooks is not declared (set true or false)'
        cfg_aliasExtension     = 'config.alias "{0}" should not have a .cmd/.exe/.bat suffix'
        cfg_duplicateId        = 'config.id "{0}" is already used by "{1}" (id must be globally unique, generate a new UUID)'
        cfg_idChanged          = 'config.id was changed (id must stay stable, restore the old id)'
        i18n_spacing           = 'Chinese and English must be separated by a space at {0}: "{1}"'
        noIssues               = 'No issues found'
        moreItems              = '… and {0} more'
    }
    'zh-CN' = @{
        title                  = '补全检查结果'
        secSchema              = 'Schema'
        secConfig              = 'Config'
        secHooks               = 'Hooks'
        secCompare             = 'Compare'
        version                = 'CLI 版本基线'
        versionChanged         = 'CLI 版本基线已变更'
        versionOld             = '旧'
        versionNew             = '新'
        cat_missingInTarget    = '缺少的项'
        cat_extraInTarget      = '多余的项'
        cat_typeMismatch       = '类型不一致'
        cat_semanticMismatch   = '语义不匹配'
        cat_valueDiff          = '值不同'
        cat_duplicateItems     = '重复项'
        cat_untranslated       = '未翻译内容'
        cat_meaninglessUsage   = '无意义 usage 行'
        cat_missingUsage       = '缺少 usage 行'
        cat_duplicateOptions   = 'global_option 重复'
        cat_usageOrder         = 'usage 顺序'
        cat_usageTooSimple     = 'usage 过于简单'
        cat_usageSeparator     = 'usage 分隔符'
        cat_optionMissingNext  = '带值选项缺少 next'
        cat_forbiddenEmptyNext = '命令禁止空 next'
        cat_usageRootPrefix    = 'usage 根前缀'
        cat_rate               = '翻译完成度'
        cfg_missingLanguage    = 'config.json 缺少 language 数组'
        cfg_missingVersion     = 'config.json 缺少 version（写这份补全时逐条对照过的 CLI 版本）'
        cfg_missingFile        = '缺少 {0}（必需）'
        cfg_langNoFile         = 'config.language 含 "{0}" 但 language/{0}.json 不存在'
        cfg_fileNoLang         = 'language/{0}.json 存在但 config.language 未声明'
        cfg_hooksFlagNoFile    = 'config.hooks 为 true/false 但 hooks.lua 不存在'
        cfg_hooksFileNoFlag    = 'hooks.lua 存在但 config.hooks 未声明（请设为 true 或 false）'
        cfg_aliasExtension     = 'config.alias "{0}" 不应含 .cmd/.exe/.bat 后缀'
        cfg_duplicateId        = 'config.id "{0}" 已被 "{1}" 使用（id 必须全局唯一，请生成新的 UUID）'
        cfg_idChanged          = 'config.id 已改动（id 必须保持稳定，请还原）'
        i18n_spacing           = '中英之间需空格于 {0}："{1}"'
        noIssues               = '未发现问题'
        moreItems              = '… 还有 {0} 条'
    }
}

function Get-Sections {
    # One section per issue category.
    # Render each to lines first, so the cap lives in one place instead of in every category's loop.
    # Full (uncapped) lines; callers apply $MaxItemsPerSection when printing.
    param($Entry, [string]$Lang)
    $m = $L[$Lang]
    $sections = [System.Collections.Generic.List[object]]::new()

    if ($Entry.issues.schema.Count) {
        $lines = foreach ($i in $Entry.issues.schema) {
            if ($i.code) {
                $tpl = $m[$i.code]
                $txt = if ($i.args.Count) { $tpl -f $i.args } else { $tpl }
                "$($i.file): $txt"
            }
            else { "$($i.file): $($i.text)" }
        }
        $sections.Add([pscustomobject]@{ title = $m.secSchema; lines = @($lines) })
    }
    if ($Entry.issues.config.Count) {
        $lines = foreach ($i in $Entry.issues.config) {
            if ($i.code -eq 'cfg_schema') { "$($i.args[0])" }
            else {
                $tpl = $m[$i.code]
                $txt = if ($i.args.Count) { $tpl -f $i.args } else { $tpl }
                $txt
            }
        }
        $sections.Add([pscustomobject]@{ title = $m.secConfig; lines = @($lines) })
    }
    if ($Entry.issues.hooks.Count) {
        $sections.Add([pscustomobject]@{ title = $m.secHooks; lines = @(foreach ($i in $Entry.issues.hooks) { "$($i.text)" }) })
    }
    if ($Entry.issues.compare.Count) {
        $lines = foreach ($i in $Entry.issues.compare) {
            if ($i.category -eq 'rate') { "[$($i.lang)] $($m.cat_rate): $($i.path)%" }
            else {
                $label = $m["cat_$($i.category)"]
                if (-not $label) { $label = $i.category }
                "[$($i.lang)] ${label}: $($i.path)"
            }
        }
        $sections.Add([pscustomobject]@{ title = $m.secCompare; lines = @($lines) })
    }
    return $sections
}

function Get-Report {
    param([array]$Results, [string]$Lang)
    $m = $L[$Lang]
    $sb = [System.Text.StringBuilder]::new()

    if (-not $NoTitle) {
        [void]$sb.AppendLine("## $($m.title)")
        [void]$sb.AppendLine('')
    }

    # Dead-target counts, derived from the full records once.
    $deadCounts = @{}
    foreach ($f in $HookTargetDetails) {
        if (-not $deadCounts.ContainsKey($f.completion)) { $deadCounts[$f.completion] = 0 }
        $deadCounts[$f.completion] += 1
    }

    # One section per completion, failed first — the same classification as the PR comment, so a local report reads exactly like the bot writes.
    $ordered = @(@($Results | Where-Object { $_.hasIssues })) + @($Results | Where-Object { -not $_.hasIssues })
    foreach ($r in $ordered) {
        $mark = if ($r.hasIssues) { '❌ ' } else { '' }
        [void]$sb.AppendLine("### $mark$($r.name)")
        [void]$sb.AppendLine('')
        $sCell = if ($r.issues.schema.Count) { "❌ $($r.issues.schema.Count)" } else { '✅' }
        $cCell = if ($r.issues.config.Count) { "❌ $($r.issues.config.Count)" } else { '✅' }
        $deadTargets = 0
        if ($deadCounts.ContainsKey($r.name)) { $deadTargets = $deadCounts[$r.name] }
        $hCell = if (-not $r.hasHooks) { '—' }
        elseif ($r.issues.hooks.Count) { "❌ $($r.issues.hooks.Count)" }
        elseif ($deadTargets) { "❌ $deadTargets" }
        else { '📝' }
        $pCell = if ($r.issues.compare.Count) { "❌ $($r.issues.compare.Count)" } else { '✅' }
        [void]$sb.AppendLine("> $($m.secSchema) $sCell · $($m.secConfig) $cCell · $($m.secHooks) $hCell · $($m.secCompare) $pCell")
        [void]$sb.AppendLine('')
        if ($r.version) {
            $verLines = if ($VersionChanged.ContainsKey($r.name)) {
                @(
                    ('> {0}:' -f $m.versionChanged),
                    ('> - {0}: `{1}`' -f $m.versionOld, $VersionChanged[$r.name]),
                    ('> - {0}: `{1}`' -f $m.versionNew, $r.version)
                )
            }
            else { @(('> {0}: `{1}`' -f $m.version, $r.version)) }
            foreach ($vl in $verLines) { [void]$sb.AppendLine($vl) }
            [void]$sb.AppendLine('')
        }

        $dead = @($HookTargetDetails | Where-Object { $_.completion -eq $r.name })
        if ($dead.Count -gt 0) {
            [void]$sb.AppendLine('> [!CAUTION]')
            [void]$sb.AppendLine('>')
            [void]$sb.AppendLine('> **Dead hook targets (`psc.on`)**')
            [void]$sb.AppendLine('>')
            foreach ($f in $dead) {
                $loc = $f.target
                if ($f.option) { $loc += " [$($f.option)]" }
                [void]$sb.AppendLine(('> - `{0}` — {1}' -f $loc, $f.reason))
            }
            [void]$sb.AppendLine('')
        }
        if ($IdChanged -contains $r.name) {
            [void]$sb.AppendLine('> [!CAUTION]')
            [void]$sb.AppendLine('>')
            [void]$sb.AppendLine('> **The id changed**')
            [void]$sb.AppendLine('>')
            [void]$sb.AppendLine('> - The `id` in `config.json` is not the same as before.')
            [void]$sb.AppendLine('> - This breaks rename detection.')
            [void]$sb.AppendLine('> - Please change it back.')
            [void]$sb.AppendLine('')
        }
        if ($RunUsage.ContainsKey($r.name)) {
            [void]$sb.AppendLine('> [!WARNING]')
            [void]$sb.AppendLine('>')
            [void]$sb.AppendLine(('> - `{0}` uses {1} in hooks.lua.' -f $r.name, $RunUsage[$r.name]))
            [void]$sb.AppendLine('> - Please review the hooks code.')
            [void]$sb.AppendLine('')
        }

        # A completion with no manifest section of its own (only a dead hook target) shows the badge and its CAUTION above, nothing more.
        foreach ($sec in (Get-Sections -Entry $r -Lang $Lang)) {
            [void]$sb.AppendLine("#### $($sec.title)")
            [void]$sb.AppendLine('')
            $shown = 0
            foreach ($line in $sec.lines) {
                if ($shown -ge $MaxItemsPerSection) { break }
                [void]$sb.AppendLine("- $line")
                $shown++
            }
            if ($sec.lines.Count -gt $MaxItemsPerSection) {
                [void]$sb.AppendLine("- $($m.moreItems -f ($sec.lines.Count - $MaxItemsPerSection))")
            }
            [void]$sb.AppendLine('')
        }
    }

    return $sb.ToString()
}

$results = [System.Collections.Generic.List[object]]::new()

function Get-AjvPath {
    # Hard dependency.
    $cmd = Get-Command ajv -ErrorAction SilentlyContinue
    if (-not $cmd) {
        throw @'
JSON Schema validator not found on PATH.

Install it with:
  npm install --global @jirutka/ajv-cli

It is a hard dependency of validate-completion.ps1, because Test-Json reports the
wrong path for schema errors and drops every `errorMessage` in schema/*.json --
messages VSCode does show.
'@
    }
    return $cmd.Source
}

function ConvertTo-ReadablePath {
    # JSON Pointer /next/0/option/0/tip/0 -> next[0].option[0].tip[0]
    param([string]$Pointer)
    if ([string]::IsNullOrEmpty($Pointer) -or $Pointer -eq '/') { return '(root)' }
    $out = ''
    foreach ($seg in (($Pointer.TrimStart('/')) -split '/')) {
        $seg = $seg -replace '~1', '/' -replace '~0', '~'
        if ($seg -match '^\d+$') { $out += "[$seg]" }
        elseif ($out -eq '') { $out = $seg }
        else { $out += ".$seg" }
    }
    return $out
}

function Get-JsonErrors {
    param([string]$FilePath, [string]$SchemaFile)

    $ajv = Get-AjvPath
    # @jirutka/ajv-cli (replaces ajv-cli).
    # --strict=false: the schemas carry `markdownDescription`, a VSCode-only annotation that ajv's strict mode rejects as an unknown keyword.
    # --errors=json: the default `pretty` format is human-readable text and cannot be parsed as JSON.
    # With `--errors=json` the error array goes to stdout (`<file> valid|invalid` and warnings stay on stderr).
    # --all-errors: without it ajv stops at the first failure, which is exactly the round-trip-by-round-trip cost this replaced.
    # Data files are positional (`--` guards paths starting with `-`); the old ajv-cli `-d` flag no longer exists.
    # `--merge-errors` keeps its default (true): one concise entry per instance path (`message` + `instancePath` + `schemaPath`), which is all the reader below consumes.
    # --validate-formats=false: `format` (only `uri` on `meta.url`) has no validator without the ajv-formats package, so ajv only warns (`unknown format "uri" ignored`) and ignores it.
    # The real URL check is the `pattern` / `not` rules, which still fire.
    # The flag just silences the warning (two lines per file on stderr); validation is unchanged.
    $raw = & $ajv validate --strict=false --all-errors --errors=json --validate-formats=false -s $SchemaFile -- $FilePath 2>&1
    $exit = $LASTEXITCODE
    if ($exit -eq 0) { return @() }

    $text = ($raw | Out-String)
    $start = $text.IndexOf('[')
    if ($start -lt 0) {
        # ajv failed before validating (bad schema, unreadable file, ...)
        return @(($text -replace '\s+', ' ').Trim())
    }

    $errs = @()
    try { $errs = @($text.Substring($start) | ConvertFrom-Json) }
    catch { return @(($text -replace '\s+', ' ').Trim()) }
    if ($errs.Count -eq 0) { return @() }

    $msgs = foreach ($e in $errs) {
        '{0}: {1}  [{2}]' -f (ConvertTo-ReadablePath $e.instancePath), $e.message, $e.schemaPath
    }
    return @($msgs)
}

function Get-ConfigIssues {
    param([hashtable]$Config, [string[]]$LangFileNames, [bool]$HasHooks)
    $issues = [System.Collections.Generic.List[object]]::new()

    if (-not $Config.ContainsKey('language') -or @($Config['language']).Count -eq 0) {
        $issues.Add(@{ code = 'cfg_missingLanguage'; args = @() })
    }
    else {
        $cfgLangs = @($Config['language'])
        foreach ($l in $cfgLangs) {
            if ($l -notin $LangFileNames) { $issues.Add(@{ code = 'cfg_langNoFile'; args = @($l) }) }
        }
        foreach ($f in $LangFileNames) {
            if ($f -notin $cfgLangs) { $issues.Add(@{ code = 'cfg_fileNoLang'; args = @($f) }) }
        }
    }

    if (-not $Config.ContainsKey('version')) {
        $issues.Add(@{ code = 'cfg_missingVersion'; args = @() })
    }

    if ($Config.ContainsKey('hooks')) {
        # hooks: true or false both declare a hooks.lua (false = present but disabled by default).
        if (-not $HasHooks) { $issues.Add(@{ code = 'cfg_hooksFlagNoFile'; args = @() }) }
    }
    else {
        if ($HasHooks) { $issues.Add(@{ code = 'cfg_hooksFileNoFlag'; args = @() }) }
    }

    if ($Config.ContainsKey('alias')) {
        foreach ($a in @($Config['alias'])) {
            if ($a -match '\.(cmd|exe|bat)$') { $issues.Add(@{ code = 'cfg_aliasExtension'; args = @($a) }) }
        }
    }

    return $issues
}

function Get-IdIssues {
    param([string[]]$Names, [string]$Root, [string]$CompletionsDir)
    $issuesByName = @{}

    # Baseline: completions.json In CI the workspace holds base/ and pr/ side by side (check-completion.yml), so prefer the trusted base index; locally fall back to the repo index.
    $localIndex = Join-Path $Root 'completions.json'
    $baseIndex = Join-Path (Split-Path -Parent $Root) 'base/completions.json'
    $baselineFile = $localIndex
    if ($env:GITHUB_ACTIONS -and (Test-Path -LiteralPath $baseIndex)) { $baselineFile = $baseIndex }

    $baselineIdToNames = @{}
    $baselineNameToId = @{}
    try {
        if (Test-Path -LiteralPath $baselineFile) {
            $idx = Get-Content -LiteralPath $baselineFile -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            $meta = $idx['meta']
            if ($meta -is [System.Collections.IDictionary]) {
                foreach ($k in $meta.Keys) {
                    $entry = $meta[$k]
                    $id = if ($entry -is [System.Collections.IDictionary]) { $entry['id'] } else { $null }
                    if ($id -is [string]) {
                        if (-not $baselineIdToNames.ContainsKey($id)) { $baselineIdToNames[$id] = [System.Collections.Generic.List[object]]::new() }
                        $baselineIdToNames[$id].Add($k)
                        if (-not $baselineNameToId.ContainsKey($k)) { $baselineNameToId[$k] = $id }
                    }
                }
            }
        }
    }
    catch { }

    $currentIds = @{}
    $currentOrigIds = @{}
    foreach ($n in $Names) {
        $cfgFile = Join-Path (Join-Path $CompletionsDir $n) 'config.json'
        try {
            $cfg = Get-Content -LiteralPath $cfgFile -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            $id = $cfg['id']
            if ($id -is [string]) {
                $currentIds[$n] = $currentOrigIds[$n] = $id
            }
        }
        catch { }
    }

    # Duplicates within the current batch (e.g. two new completions sharing one id).
    $byId = @{}
    foreach ($n in $currentIds.Keys) {
        $id = $currentIds[$n]
        if (-not $byId.ContainsKey($id)) { $byId[$id] = [System.Collections.Generic.List[object]]::new() }
        $byId[$id].Add($n)
    }
    foreach ($id in $byId.Keys) {
        if (@($byId[$id]).Count -gt 1) {
            $owners = (($byId[$id] | Sort-Object) -join ', ')
            foreach ($n in @($byId[$id])) {
                if (-not $issuesByName.ContainsKey($n)) { $issuesByName[$n] = [System.Collections.Generic.List[object]]::new() }
                $issuesByName[$n].Add(@{ code = 'cfg_duplicateId'; args = @($currentOrigIds[$n], $owners) })
            }
        }
    }

    # Duplicates against the baseline index.
    # Same name + same id is fine (update).
    # A baseline owner whose directory no longer exists is a rename, allow it.
    foreach ($n in @($currentIds.Keys)) {
        $id = $currentIds[$n]
        if (-not $baselineIdToNames.ContainsKey($id)) { continue }
        foreach ($owner in @($baselineIdToNames[$id])) {
            if ($owner -eq $n) { continue }
            if (-not (Test-Path -LiteralPath (Join-Path $CompletionsDir $owner))) { continue }
            if ($owner -in @($byId[$id])) { continue }
            if (-not $issuesByName.ContainsKey($n)) { $issuesByName[$n] = [System.Collections.Generic.List[object]]::new() }
            $issuesByName[$n].Add(@{ code = 'cfg_duplicateId'; args = @($currentOrigIds[$n], $owner) })
        }
    }

    # Stability: the same completion must keep its id.
    # A changed id breaks rename detection and orphans per-completion settings.
    # No baseline entry means a new completion with nothing to compare: skip it.
    foreach ($n in @($currentIds.Keys)) {
        if (-not $baselineNameToId.ContainsKey($n)) { continue }
        if ($currentIds[$n] -ceq $baselineNameToId[$n]) { continue }
        if (-not $issuesByName.ContainsKey($n)) { $issuesByName[$n] = [System.Collections.Generic.List[object]]::new() }
        $issuesByName[$n].Add(@{ code = 'cfg_idChanged'; args = @() })
    }

    return $issuesByName
}

function Get-HookSyntaxIssues {
    param([string]$HooksFile)
    # Lua hooks can't be checked with the PowerShell parser; only verify the file exists and is non-empty
    try {
        if ((Get-Item -LiteralPath $HooksFile).Length -eq 0) {
            return @(@{ text = 'hooks.lua is empty' })
        }
    }
    catch {
        return @(@{ text = 'hooks.lua missing' })
    }
    return @()
}

function Get-I18nSpacingIssues {
    param([string]$JsonPath)
    $issues = [System.Collections.Generic.List[object]]::new()
    try {
        $text = Get-Content -LiteralPath $JsonPath -Raw -ErrorAction Stop
        $obj = $text | ConvertFrom-Json -ErrorAction Stop
    }
    catch { return $issues }
    $pattern = '[\u4e00-\u9fff][A-Za-z]|[A-Za-z][\u4e00-\u9fff]'
    function Walk($node, $path) {
        if ($null -eq $node) { return }
        if ($node -is [System.Collections.IDictionary] -or $node -is [psobject]) {
            $props = if ($node -is [System.Collections.IDictionary]) { $node.Keys } else { $node.PSObject.Properties.Name }
            foreach ($k in $props) {
                $v = if ($node -is [System.Collections.IDictionary]) { $node[$k] } else { $node.PSObject.Properties[$k].Value }
                $curPath = if ($path) { "$path/$k" } else { $k }
                if ($k -in @('tip', 'usage', 'example', 'description')) {
                    $arr = @()
                    if ($v -is [System.Collections.IList] -and -not ($v -is [string])) { $arr = $v }
                    elseif ($v -is [string]) { $arr = @($v) }
                    if ($arr.Count -gt 0) {
                        for ($i = 0; $i -lt $arr.Count; $i++) {
                            $item = $arr[$i]
                            $itemPath = "$curPath[$i]"
                            if ($item -is [string] -and $item -match $pattern) {
                                $issues.Add(@{ code = 'i18n_spacing'; args = @($itemPath, $item); file = [System.IO.Path]::GetFileName($JsonPath) })
                            }
                            elseif ($item -is [System.Collections.IDictionary] -or $item -is [psobject]) {
                                $cmd = if ($item -is [System.Collections.IDictionary]) { $item['cmd'] } else { $item.cmd }
                                $desc = if ($item -is [System.Collections.IDictionary]) { $item['desc'] } else { $item.desc }
                                if ($cmd -is [string] -and $cmd -match $pattern) { $issues.Add(@{ code = 'i18n_spacing'; args = @("$itemPath/cmd", $cmd); file = [System.IO.Path]::GetFileName($JsonPath) }) }
                                if ($desc -is [string] -and $desc -match $pattern) { $issues.Add(@{ code = 'i18n_spacing'; args = @("$itemPath/desc", $desc); file = [System.IO.Path]::GetFileName($JsonPath) }) }
                            }
                        }
                        continue
                    }
                }
                if ($v -is [System.Collections.IDictionary] -or $v -is [psobject] -or $v -is [System.Collections.IList]) {
                    Walk $v $curPath
                }
            }
        }
        elseif ($node -is [System.Collections.IList] -and -not ($node -is [string])) {
            for ($i = 0; $i -lt $node.Count; $i++) {
                Walk $node[$i] "$path[$i]"
            }
        }
    }
    Walk $obj ''
    return $issues
}

foreach ($name in $CompletionList) {
    if (-not $name.Trim()) { continue }
    if ($name.StartsWith('.')) { continue }
    $completionDir = Join-Path $completionsDir $name
    $langDir = Join-Path $completionDir 'language'
    $configFile = Join-Path $completionDir 'config.json'
    $hooksFile = Join-Path $completionDir 'hooks.lua'

    $entry = @{
        name      = $name
        files     = @()
        issues    = @{
            schema  = [System.Collections.Generic.List[object]]::new()
            config  = [System.Collections.Generic.List[object]]::new()
            hooks   = [System.Collections.Generic.List[object]]::new()
            compare = [System.Collections.Generic.List[object]]::new()
        }
        hasIssues = $false
        hasHooks  = $false
        fileCount = 0
        version   = $null
    }

    # Probe each path once; every check below reads these instead of re-stat'ing.
    $hasDir = Test-Path -LiteralPath $completionDir
    $hasLangDir = Test-Path -LiteralPath $langDir
    $hasConfig = Test-Path -LiteralPath $configFile
    $hasHooks = Test-Path -LiteralPath $hooksFile
    $langFiles = if ($hasLangDir) { @(Get-ChildItem -LiteralPath $langDir -Filter '*.json') } else { @() }
    $langFileNames = @($langFiles | ForEach-Object { $_.BaseName })

    $fileList = @()
    if ($hasConfig) { $fileList += 'config.json' }
    if ($hasHooks) { $fileList += 'hooks.lua' }
    if ($hasLangDir) { $fileList += @($langFiles | ForEach-Object { "language/$($_.Name)" }) }
    $entry.files = $fileList
    $entry.fileCount = $fileList.Count

    # config.json is required.
    # Only flag a missing one when the completion directory itself exists, so a deliberately removed completion stays clean.
    if ($hasDir -and -not $hasConfig) {
        $entry.issues.config.Add(@{ code = 'cfg_missingFile'; args = @('config.json') })
    }

    foreach ($f in $langFiles) {
        $errs = Get-JsonErrors -FilePath $f.FullName -SchemaFile $manifestSchema
        foreach ($e in $errs) { $entry.issues.schema.Add(@{ file = $f.Name; text = $e }) }
        $i18n = Get-I18nSpacingIssues -JsonPath $f.FullName
        foreach ($e in $i18n) { $entry.issues.schema.Add($e) }
    }

    if ($hasConfig) {
        # One read serves the schema check and the parsed form below.
        $cfgText = Get-Content -LiteralPath $configFile -Raw
        $errs = Get-JsonErrors -FilePath $configFile -SchemaFile $configSchema
        foreach ($e in $errs) { $entry.issues.config.Add(@{ code = 'cfg_schema'; args = @($e) }) }

        $config = $null
        try { $config = $cfgText | ConvertFrom-Json -AsHashtable } catch { $config = $null }
        if ($config) {
            $cfgIssues = Get-ConfigIssues -Config $config -LangFileNames $langFileNames -HasHooks $hasHooks
            foreach ($i in $cfgIssues) { $entry.issues.config.Add($i) }
            if ($config['version'] -is [string] -and $config['version'] -ne '') {
                $entry.version = $config['version']
            }
        }
    }

    if ($hasHooks) {
        $entry.hasHooks = $true
        $hookIssues = Get-HookSyntaxIssues -HooksFile $hooksFile
        foreach ($i in $hookIssues) { $entry.issues.hooks.Add($i) }
    }

    $entry.hasIssues = $entry.issues.schema.Count -gt 0 -or $entry.issues.config.Count -gt 0 -or $entry.issues.hooks.Count -gt 0 -or $entry.issues.compare.Count -gt 0

    $results.Add([pscustomobject]$entry)
}

# id uniqueness across completions (baseline: base/completions.json in CI, else local completions.json)
if ($results.Count -gt 0) {
    $idIssues = Get-IdIssues -Names @($results | ForEach-Object { $_.name }) -Root $root -CompletionsDir $completionsDir
    foreach ($entry in $results) {
        if ($idIssues.ContainsKey($entry.name)) {
            foreach ($i in $idIssues[$entry.name]) { $entry.issues.config.Add($i) }
            $entry.hasIssues = $true
        }
    }
}

# compare-json processes all completions at once
if ($results.Count -gt 0) {
    $allNames = @($results | ForEach-Object { $_.name })
    $compareOut = & (Join-Path $PSScriptRoot 'compare-json.ps1') @($allNames) -Json 2>$null | Out-String
    try {
        $compareData = $compareOut | ConvertFrom-Json -ErrorAction Stop
        foreach ($r in $compareData.results) {
            $entry = $results | Where-Object { $_.name -eq $r.completion } | Select-Object -First 1
            if (-not $entry) { continue }
            foreach ($cat in $r.issues.PSObject.Properties) {
                foreach ($p in $cat.Value) {
                    if ($p) { $entry.issues.compare.Add(@{ lang = $r.lang; category = $cat.Name; path = $p }) }
                }
            }
            if ($r.rate -lt 100) { $entry.issues.compare.Add(@{ lang = $r.lang; category = 'rate'; path = "$($r.rate)" }) }
            $entry.hasIssues = $entry.hasIssues -or $entry.issues.compare.Count -gt 0
        }
    }
    catch {
        Write-Warning $_.Exception.Message
    }
}

# A dead psc.on target is a failure even when the manifest itself is clean.
# A changed stable id breaks rename detection, so it fails too.
foreach ($entry in $results) {
    if (@($HookTargetDetails | Where-Object { $_.completion -eq $entry.name }).Count -gt 0) {
        $entry.hasIssues = $true
    }
    if ($IdChanged -contains $entry.name) { $entry.hasIssues = $true }
}

if ($OutFile) {
    Get-Report -Results $results -Lang $Lang | Out-File -FilePath $OutFile -Encoding utf8
}

if ($Json) {
    $payload = foreach ($entry in $results) {
        [pscustomobject]@{
            name      = $entry.name
            hasIssues = [bool]$entry.hasIssues
            hasHooks  = [bool]$entry.hasHooks
            version   = $entry.version
            counts    = [pscustomobject]@{
                schema  = $entry.issues.schema.Count
                config  = $entry.issues.config.Count
                hooks   = $entry.issues.hooks.Count
                compare = $entry.issues.compare.Count
            }
        }
    }
    if ($results.Count -eq 0) { '[]' } else { @($payload) | ConvertTo-Json -Depth 8 }
    return
}

$results
