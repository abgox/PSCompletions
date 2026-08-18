#Requires -Version 7.0

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
    .\scripts\validate-completion.ps1 git cargo
    .\scripts\validate-completion.ps1 -All -Lang zh-CN -OutFile result-zh.md
#>

param(
    [Parameter(Position = 0, ValueFromRemainingArguments)]
    [string[]]$CompletionList,
    [switch]$All,
    [ValidateSet('en-US', 'zh-CN')]
    [string]$Lang = 'en-US',
    [string]$OutFile
)

Set-StrictMode -Off

$root = Split-Path -Parent $PSScriptRoot
$completionsDir = Join-Path $root 'completions'
$manifestSchema = Join-Path $root 'schema\completion-manifest.en-US.json'
$configSchema = Join-Path $root 'schema\completion-config.en-US.json'

if ($All) {
    $CompletionList = @(Get-ChildItem -LiteralPath $completionsDir -Directory | ForEach-Object { $_.Name })
}

$L = @{
    'en-US' = @{
        title                = 'Completion Validation'
        checked              = 'Checked **{0}** completions | ✅ **{1}** passed | ❌ **{2}** have issues'
        colCompletion        = 'Completion'
        colSchema            = 'Schema'
        colConfig            = 'Config'
        colHooks             = 'Hooks'
        colCompare           = 'Compare'
        secSchema            = 'Schema'
        secConfig            = 'Config'
        secHooks             = 'Hooks'
        secCompare           = 'Compare'
        filesLabel           = 'Files'
        cat_missingInTarget  = 'Missing items'
        cat_extraInTarget    = 'Extra items'
        cat_typeMismatch     = 'Type mismatch'
        cat_semanticMismatch = 'Semantic mismatch'
        cat_valueDiff        = 'Value difference'
        cat_duplicateItems   = 'Duplicate items'
        cat_untranslated     = 'Untranslated content'
        cat_meaninglessUsage = 'Meaningless usage line'
        cat_missingUsage     = 'Missing usage line'
        cat_usageOrder       = 'Usage order'
        cat_usageTooSimple   = 'Usage too simple'
        cat_usageSeparator   = 'Usage separator'
        cat_rate             = 'Translation rate'
        cfg_missingLanguage  = 'config.json is missing the "language" array'
        cfg_langNoFile       = 'config.language has "{0}" but language/{0}.json does not exist'
        cfg_fileNoLang       = 'language/{0}.json exists but is not declared in config.language'
        cfg_hooksFlagNoFile  = 'config.hooks=true/false but hooks.lua does not exist'
        cfg_hooksFileNoFlag  = 'hooks.lua exists but config.hooks is not declared (set true or false)'
        cfg_aliasExtension   = 'config.alias "{0}" should not have a .cmd/.exe/.bat suffix'
        noIssues             = 'No issues found'
    }
    'zh-CN' = @{
        title                = '补全检查结果'
        checked              = '检查 **{0}** 个补全 | ✅ **{1}** 通过 | ❌ **{2}** 有问题'
        colCompletion        = '补全'
        colSchema            = 'Schema'
        colConfig            = '配置'
        colHooks             = 'Hooks'
        colCompare           = '比对'
        secSchema            = 'Schema'
        secConfig            = '配置'
        secHooks             = 'Hooks'
        secCompare           = '比对'
        filesLabel           = '文件'
        cat_missingInTarget  = '缺少的项'
        cat_extraInTarget    = '多余的项'
        cat_typeMismatch     = '类型不一致'
        cat_semanticMismatch = '语义不匹配'
        cat_valueDiff        = '值不同'
        cat_duplicateItems   = '重复项'
        cat_untranslated     = '未翻译内容'
        cat_meaninglessUsage = '无意义 usage 行'
        cat_missingUsage     = '缺少 usage 行'
        cat_duplicateOptions = 'global_option 重复'
        cat_usageOrder       = 'usage 顺序'
        cat_usageTooSimple   = 'usage 过于简单'
        cat_usageSeparator   = 'usage 分隔符'
        cat_rate             = '翻译完成度'
        cfg_missingLanguage  = 'config.json 缺少 language 数组'
        cfg_langNoFile       = 'config.language 含 "{0}" 但 language/{0}.json 不存在'
        cfg_fileNoLang       = 'language/{0}.json 存在但 config.language 未声明'
        cfg_hooksFlagNoFile  = 'config.hooks 为 true/false 但 hooks.lua 不存在'
        cfg_hooksFileNoFlag  = 'hooks.lua 存在但 config.hooks 未声明（请设为 true 或 false）'
        cfg_aliasExtension   = 'config.alias "{0}" 不应含 .cmd/.exe/.bat 后缀'
        noIssues             = '未发现问题'
    }
}

function Get-Report {
    param([array]$Results, [string]$Lang)
    $m = $L[$Lang]
    $sb = [System.Text.StringBuilder]::new()

    $ok = @($Results | Where-Object { -not $_.hasIssues }).Count
    $bad = @($Results | Where-Object { $_.hasIssues }).Count

    [void]$sb.AppendLine("## $($m.title)")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine(($m.checked -f $Results.Count, $ok, $bad))
    [void]$sb.AppendLine('')

    [void]$sb.AppendLine("| $($m.colCompletion) | $($m.colSchema) | $($m.colConfig) | $($m.colHooks) | $($m.colCompare) |")
    [void]$sb.AppendLine('| --- | --- | --- | --- | --- |')
    foreach ($r in $Results) {
        $s = if ($r.issues.schema.Count) { "❌ $($r.issues.schema.Count)" } else { '✅' }
        $c = if ($r.issues.config.Count) { "❌ $($r.issues.config.Count)" } else { '✅' }
        $h = if (-not $r.hasHooks) { '' } elseif ($r.issues.hooks.Count) { "❌ $($r.issues.hooks.Count)" } else { '📝' }
        $p = if ($r.issues.compare.Count) { "❌ $($r.issues.compare.Count)" } else { '✅' }
        [void]$sb.AppendLine("| **$($r.name)** | $s | $c | $h | $p |")
    }
    [void]$sb.AppendLine('')

    foreach ($r in $Results | Where-Object { $_.hasIssues }) {
        [void]$sb.AppendLine('<details>')
        [void]$sb.AppendLine("<summary>❌ $($r.name)</summary>")
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine("**$($m.filesLabel)**: $($r.files -join ', ')")
        [void]$sb.AppendLine('')

        if ($r.issues.schema.Count) {
            [void]$sb.AppendLine("**$($m.secSchema)**")
            foreach ($i in $r.issues.schema) { [void]$sb.AppendLine("- $($i.file): $($i.text)") }
            [void]$sb.AppendLine('')
        }
        if ($r.issues.config.Count) {
            [void]$sb.AppendLine("**$($m.secConfig)**")
            foreach ($i in $r.issues.config) {
                if ($i.code -eq 'cfg_schema') {
                    [void]$sb.AppendLine("- $($i.args[0])")
                }
                else {
                    $tpl = $m[$i.code]
                    $txt = if ($i.args.Count) { $tpl -f $i.args } else { $tpl }
                    [void]$sb.AppendLine("- $txt")
                }
            }
            [void]$sb.AppendLine('')
        }
        if ($r.issues.hooks.Count) {
            [void]$sb.AppendLine("**$($m.secHooks)**")
            foreach ($i in $r.issues.hooks) { [void]$sb.AppendLine("- $($i.text)") }
            [void]$sb.AppendLine('')
        }
        if ($r.issues.compare.Count) {
            [void]$sb.AppendLine("**$($m.secCompare)**")
            foreach ($i in $r.issues.compare) {
                if ($i.category -eq 'rate') {
                    [void]$sb.AppendLine("- [$($i.lang)] $($m.cat_rate): $($i.path)%")
                }
                else {
                    $label = $m["cat_$($i.category)"]
                    if (-not $label) { $label = $i.category }
                    [void]$sb.AppendLine("- [$($i.lang)] ${label}: $($i.path)")
                }
            }
            [void]$sb.AppendLine('')
        }
        [void]$sb.AppendLine('</details>')
        [void]$sb.AppendLine('')
    }

    if ($bad -eq 0) {
        [void]$sb.AppendLine("> ✅ $($m.noIssues)")
        [void]$sb.AppendLine('')
    }

    return $sb.ToString()
}

$results = [System.Collections.Generic.List[object]]::new()

function Get-JsonErrors {
    param([string]$JsonText, [string]$SchemaFile)
    $schema = Get-Content -LiteralPath $SchemaFile -Raw
    try {
        $null = $JsonText | Test-Json -Schema $schema -ErrorAction Stop
        return @()
    }
    catch {
        $msg = $_.Exception.Message
        if ($msg -match ':\s*(.*)$') { $msg = $Matches[1] }
        return @($msg)
    }
}

function Get-ConfigIssues {
    param([hashtable]$Config, [string]$LangDir)
    $issues = [System.Collections.Generic.List[object]]::new()

    if (-not $Config.ContainsKey('language') -or @($Config['language']).Count -eq 0) {
        $issues.Add(@{ code = 'cfg_missingLanguage'; args = @() })
    }
    else {
        $cfgLangs = @($Config['language'])
        $langFiles = @()
        if (Test-Path -LiteralPath $LangDir) {
            $langFiles = @(Get-ChildItem -LiteralPath $LangDir -Filter '*.json' | ForEach-Object { $_.BaseName })
        }
        foreach ($l in $cfgLangs) {
            if ($l -notin $langFiles) { $issues.Add(@{ code = 'cfg_langNoFile'; args = @($l) }) }
        }
        foreach ($f in $langFiles) {
            if ($f -notin $cfgLangs) { $issues.Add(@{ code = 'cfg_fileNoLang'; args = @($f) }) }
        }
    }

    $hooksFile = Join-Path (Split-Path -Parent $LangDir) 'hooks.lua'
    if ($Config.ContainsKey('hooks')) {
        # hooks: true or false both declare a hooks.lua (false = present but disabled by default).
        if (-not (Test-Path -LiteralPath $hooksFile)) { $issues.Add(@{ code = 'cfg_hooksFlagNoFile'; args = @() }) }
    }
    else {
        if (Test-Path -LiteralPath $hooksFile) { $issues.Add(@{ code = 'cfg_hooksFileNoFlag'; args = @() }) }
    }

    if ($Config.ContainsKey('alias')) {
        foreach ($a in @($Config['alias'])) {
            if ($a -match '\.(cmd|exe|bat)$') { $issues.Add(@{ code = 'cfg_aliasExtension'; args = @($a) }) }
        }
    }

    return $issues
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

foreach ($name in $CompletionList) {
    if (-not $name.Trim()) { continue }
    if ($name.StartsWith('.')) { continue }
    $completionDir = Join-Path $completionsDir $name
    $langDir = Join-Path $completionDir 'language'
    $configFile = Join-Path $completionDir 'config.json'
    $hooksFile = Join-Path $completionDir 'hooks.lua'

    $entry = @{
        name        = $name
        files       = @()
        issues      = @{
            schema  = [System.Collections.Generic.List[object]]::new()
            config  = [System.Collections.Generic.List[object]]::new()
            hooks   = [System.Collections.Generic.List[object]]::new()
            compare = [System.Collections.Generic.List[object]]::new()
        }
        hasIssues   = $false
        hasHooks    = $false
        fileCount   = 0
    }

    $fileList = @()
    if (Test-Path -LiteralPath $configFile) { $fileList += 'config.json' }
    if (Test-Path -LiteralPath $hooksFile) { $fileList += 'hooks.lua' }
    if (Test-Path -LiteralPath $langDir) { $fileList += @(Get-ChildItem -LiteralPath $langDir -Filter '*.json' | ForEach-Object { "language/$($_.Name)" }) }
    $entry.files = $fileList
    $entry.fileCount = $fileList.Count

    if (Test-Path -LiteralPath $langDir) {
        foreach ($f in Get-ChildItem -LiteralPath $langDir -Filter '*.json') {
            $jsonText = Get-Content -LiteralPath $f.FullName -Raw
            $errs = Get-JsonErrors -JsonText $jsonText -SchemaFile $manifestSchema
            foreach ($e in $errs) { $entry.issues.schema.Add(@{ file = $f.Name; text = $e }) }
        }
    }
    if (Test-Path -LiteralPath $configFile) {
        $cfgText = Get-Content -LiteralPath $configFile -Raw
        $errs = Get-JsonErrors -JsonText $cfgText -SchemaFile $configSchema
        foreach ($e in $errs) { $entry.issues.config.Add(@{ code = 'cfg_schema'; args = @($e) }) }
    }

    $config = $null
    if (Test-Path -LiteralPath $configFile) {
        try { $config = Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json -AsHashtable } catch { $config = $null }
        if ($config) {
            $cfgIssues = Get-ConfigIssues -Config $config -LangDir $langDir
            foreach ($i in $cfgIssues) { $entry.issues.config.Add($i) }
        }
    }

    if (Test-Path -LiteralPath $hooksFile) {
        $entry.hasHooks = $true
        $hookIssues = Get-HookSyntaxIssues -HooksFile $hooksFile
        foreach ($i in $hookIssues) { $entry.issues.hooks.Add($i) }
    }

    $entry.hasIssues = $entry.issues.schema.Count -gt 0 -or $entry.issues.config.Count -gt 0 -or $entry.issues.hooks.Count -gt 0 -or $entry.issues.compare.Count -gt 0

    $results.Add([pscustomobject]$entry)
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

if ($OutFile) {
    Get-Report -Results $results -Lang $Lang | Out-File -FilePath $OutFile -Encoding utf8
}

$results
