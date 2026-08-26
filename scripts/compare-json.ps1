#Requires -Version 7.0

param(
    [Parameter(Position = 0, ValueFromRemainingArguments)]
    [array]$CompletionList,
    [ArgumentCompletions('en-US', 'zh-CN')]
    [string]$BaseLang,
    [switch]$All,
    [switch]$Json
)

Set-StrictMode -Off

. $PSScriptRoot\utils.ps1

# Compiled diff engine (scripts/psc-tools.cs); consumes the Hashtables parsed below.
if (-not ('PscTools.Diff' -as [type])) {
    try { Add-Type -Path "$PSScriptRoot\psc-tools.cs" } catch { Write-Verbose "PscTools unavailable: $_" }
}

$textPath = "$PSScriptRoot/language/$PSCulture.json"
if (!(Test-Path -LiteralPath $textPath)) {
    $textPath = "$PSScriptRoot/language/en-US.json"
}
$text = Get-Content -Path $textPath -Encoding utf8 | ConvertFrom-Json

if (!$PSCompletions) { . $PSScriptRoot\..\module\PSCompletions\PSCompletions.ps1 }
$PSCompletions.initialize($true)

$text = $text.'compare-json'

function outText {
    param($text)
    if ($text -is [array]) { $text = $text -join "`n" }
    $PSCompletions.write_with_color($PSCompletions.replace_content($text))
}

if (-not $BaseLang) { $BaseLang = 'en-US' }
if (-not $CompletionList) {
    if ($All) {
        $CompletionList = (Get-ChildItem "$PSScriptRoot\..\completions" -Directory).Name
    }
    else {
        $CompletionList = Get-RecentCompletions -CompletionsDir "$PSScriptRoot\..\completions"
        if ($CompletionList.Count -eq 0) {
            outText $text.noRecent
            return
        }
    }
}

function Compare-Lang {
    param (
        [string]$baseJson,
        [string]$targetJson,
        [string]$targetLang
    )

    $baseContent = Get-Content -Path $baseJson -Raw | ConvertFrom-Json -AsHashtable
    $targetContent = Get-Content -Path $targetJson -Raw | ConvertFrom-Json -AsHashtable

    $opts = [PscTools.DiffOptions]@{
        BaseLang           = $BaseLang
        TargetLang         = $targetLang
        CompletionName     = $CompletionName
        ReasonCount        = $text.reasonCount
        ReasonType         = $text.reasonType
        ReasonMissingField = $text.reasonMissingField
        ReasonCmdValue     = $text.reasonCmdValue
        ReasonNextValue    = $text.reasonNextValue
    }

    $r = [PscTools.Diff]::Run($baseContent, $targetContent, $opts)

    function Convert-Issues([System.Collections.Generic.List[PscTools.DiffIssue]]$list) {
        $out = @()
        foreach ($i in $list) {
            $out += @{ path = $i.Path; name = $i.Name; reason = $i.Reason }
        }
        return , $out
    }

    $stats = @{
        totalTips          = $r.TotalTips
        translatedTips     = $r.TranslatedTips
        missingInTarget    = Convert-Issues $r.MissingInTarget
        extraInTarget      = Convert-Issues $r.ExtraInTarget
        typeMismatch       = Convert-Issues $r.TypeMismatch
        semanticMismatch   = Convert-Issues $r.SemanticMismatch
        valueDiff          = Convert-Issues $r.ValueDiff
        untranslated       = Convert-Issues $r.Untranslated
        duplicateItems     = Convert-Issues $r.DuplicateItems
        meaninglessUsage   = Convert-Issues $r.MeaninglessUsage
        missingUsage       = Convert-Issues $r.MissingUsage
        duplicateOptions   = Convert-Issues $r.DuplicateOptions
        usageOrder         = Convert-Issues $r.UsageOrder
        usageTooSimple     = Convert-Issues $r.UsageTooSimple
        usageSeparator     = Convert-Issues $r.UsageSeparator
        optionMissingNext  = Convert-Issues $r.OptionMissingNext
        forbiddenEmptyNext = Convert-Issues $r.ForbiddenEmptyNext
        usageRootPrefix    = Convert-Issues $r.UsageRootPrefix
    }

    $translationRate = 100
    if ($stats.totalTips -gt 0) {
        # 4 decimals: with huge manifests (aws ~150k tips), 2 decimals rounds small deficits up to a fake 100%
        $translationRate = [Math]::Round(($stats.translatedTips / $stats.totalTips) * 100, 4)
    }

    return @{
        stats = $stats
        rate  = $translationRate
    }
}

$allResults = @()

foreach ($CompletionName in $CompletionList) {
    if (!$CompletionName.Trim()) {
        outText $text.invalidName
        continue
    }
    $langDir = [System.IO.Path]::Combine($PSScriptRoot, '..', 'completions', $CompletionName, 'language')
    if (!(Test-Path -LiteralPath $langDir)) {
        continue
    }
    $allLangFiles = Get-ChildItem -Path $langDir -Filter '*.json' | ForEach-Object { $_.BaseName }
    $otherLangs = $allLangFiles | Where-Object { $_ -ne $BaseLang } | Sort-Object
    if ($otherLangs.Count -eq 0) {
        continue
    }
    $baseJson = [System.IO.Path]::Combine($langDir, $BaseLang + '.json')
    if (!(Test-Path -LiteralPath $baseJson)) {
        outText $text.invalidLang
        continue
    }
    & $PSScriptRoot\sort-json.ps1 $CompletionName -Quiet

    foreach ($lang in $otherLangs) {
        $targetJson = [System.IO.Path]::Combine($langDir, $lang + '.json')
        $result = Compare-Lang $baseJson $targetJson $lang
        $stats = $result.stats

        $missing = $stats.missingInTarget.Count
        $extra = $stats.extraInTarget.Count
        $translated = $stats.translatedTips
        $total = $stats.totalTips
        $rate = $result.rate

        if ($total -eq 0) { continue }

        # Exact count comparison: a rounded rate can equal 100 even when tips are untranslated
        $hasIssues = $missing -gt 0 -or $extra -gt 0 -or $translated -ne $total -or $stats.untranslated.Count -gt 0 -or $stats.typeMismatch.Count -gt 0 -or $stats.semanticMismatch.Count -gt 0 -or $stats.valueDiff.Count -gt 0 -or $stats.duplicateItems.Count -gt 0 -or $stats.meaninglessUsage.Count -gt 0 -or $stats.missingUsage.Count -gt 0 -or $stats.duplicateOptions.Count -gt 0 -or $stats.usageOrder.Count -gt 0 -or $stats.usageTooSimple.Count -gt 0 -or $stats.usageSeparator.Count -gt 0 -or $stats.optionMissingNext.Count -gt 0 -or $stats.forbiddenEmptyNext.Count -gt 0 -or $stats.usageRootPrefix.Count -gt 0

        $allResults += @{
            completion = $CompletionName
            lang       = $lang
            stats      = $stats
            rate       = $rate
            missing    = $missing
            extra      = $extra
            translated = $translated
            total      = $total
            hasIssues  = $hasIssues
        }
    }
}

if ($Json) {
    $jsonResults = @($allResults | ForEach-Object {
            $s = $_.stats
            @{
                completion = $_.completion
                lang       = $_.lang
                hasIssues  = $_.hasIssues
                rate       = $_.rate
                issues     = @{
                    missingInTarget    = @($s.missingInTarget | ForEach-Object { $_.path })
                    extraInTarget      = @($s.extraInTarget | ForEach-Object { $_.path })
                    typeMismatch       = @($s.typeMismatch | ForEach-Object { $_.path })
                    semanticMismatch   = @($s.semanticMismatch | ForEach-Object { "$($_.path)  —  $($_.reason)" })
                    valueDiff          = @($s.valueDiff | ForEach-Object { $_.path })
                    duplicateItems     = @($s.duplicateItems | ForEach-Object { $_.path })
                    untranslated       = @($s.untranslated | ForEach-Object { $_.path })
                    meaninglessUsage   = @($s.meaninglessUsage | ForEach-Object { $_.path })
                    missingUsage       = @($s.missingUsage | ForEach-Object { $_.path })
                    duplicateOptions   = @($s.duplicateOptions | ForEach-Object { $_.path })
                    usageOrder         = @($s.usageOrder | ForEach-Object { $_.path })
                    usageTooSimple     = @($s.usageTooSimple | ForEach-Object { $_.path })
                    usageSeparator     = @($s.usageSeparator | ForEach-Object { $_.path })
                    optionMissingNext  = @($s.optionMissingNext | ForEach-Object { $_.path })
                    forbiddenEmptyNext = @($s.forbiddenEmptyNext | ForEach-Object { $_.path })
                    usageRootPrefix    = @($s.usageRootPrefix | ForEach-Object { $_.path })
                }
            }
        })
    @{ results = $jsonResults } | ConvertTo-Json -Depth 10
    return
}

$issueResults = @()
$completeResults = @()
foreach ($r in $allResults) {
    if ($r.hasIssues) {
        $issueResults += $r
    }
    else {
        $completeResults += $r
    }
}
$totalFiles = $allResults.Count
$issueFiles = $issueResults.Count
$completedFiles = $completeResults.Count

outText $text.summary

if ($issueFiles -gt 0) {
    foreach ($r in $issueResults) {
        $targetShortPath = "$($r.completion)/$($r.lang).json"
        $missing = $r.missing
        $extra = $r.extra
        $translated = $r.translated
        $total = $r.total
        $rate = $r.rate
        $count = $r.stats.untranslated.Count
        outText $text.langHeader

        if ($r.stats.missingInTarget.Count -gt 0) {
            outText $text.missingInTarget
            foreach ($item in $r.stats.missingInTarget) { outText "<@Cyan>  $($item.path)" }
        }
        if ($r.stats.extraInTarget.Count -gt 0) {
            outText $text.extraInTarget
            foreach ($item in $r.stats.extraInTarget) { outText "<@Cyan>  $($item.path)" }
        }
        if ($r.stats.typeMismatch.Count -gt 0) {
            outText $text.typeMismatch
            foreach ($item in $r.stats.typeMismatch) { outText "<@Cyan>  $($item.path)" }
        }
        if ($r.stats.semanticMismatch.Count -gt 0) {
            outText $text.semanticMismatch
            foreach ($item in $r.stats.semanticMismatch) {
                if ($item.reason) {
                    outText "<@Cyan>  $($item.path)<@Yellow>  —  $($item.reason)"
                }
                else {
                    outText "<@Cyan>  $($item.path)"
                }
            }
        }
        if ($r.stats.valueDiff.Count -gt 0) {
            outText $text.valueDiff
            foreach ($item in $r.stats.valueDiff) { outText "<@Cyan>  $($item.path)" }
        }
        if ($r.stats.duplicateItems.Count -gt 0) {
            outText $text.duplicateItems
            foreach ($item in $r.stats.duplicateItems) { outText "<@Cyan>  $($item.path)" }
        }
        if ($r.stats.untranslated.Count -gt 0) {
            outText $text.untranslated
            foreach ($item in $r.stats.untranslated) { outText "<@Cyan>  $($item.path)" }
        }
        if ($r.stats.meaninglessUsage.Count -gt 0) {
            outText $text.meaninglessUsage
            foreach ($item in $r.stats.meaninglessUsage) { outText "<@Cyan>  $($item.path)" }
        }
        if ($r.stats.missingUsage.Count -gt 0) {
            outText $text.missingUsage
            foreach ($item in $r.stats.missingUsage) { outText "<@Cyan>  $($item.path)" }
        }
        if ($r.stats.duplicateOptions.Count -gt 0) {
            outText $text.duplicateOptions
            foreach ($item in $r.stats.duplicateOptions) { outText "<@Cyan>  $($item.path)" }
        }
        if ($r.stats.usageOrder.Count -gt 0) {
            outText $text.usageOrder
            foreach ($item in $r.stats.usageOrder) { outText "<@Cyan>  $($item.path)" }
        }
        if ($r.stats.usageTooSimple.Count -gt 0) {
            outText $text.usageTooSimple
            foreach ($item in $r.stats.usageTooSimple) { outText "<@Cyan>  $($item.path)" }
        }
        if ($r.stats.usageSeparator.Count -gt 0) {
            outText $text.usageSeparator
            foreach ($item in $r.stats.usageSeparator) { outText "<@Cyan>  $($item.path)" }
        }
        if ($r.stats.optionMissingNext.Count -gt 0) {
            outText $text.optionMissingNext
            foreach ($item in $r.stats.optionMissingNext) { outText "<@Cyan>  $($item.path)" }
        }
        if ($r.stats.forbiddenEmptyNext.Count -gt 0) {
            outText $text.forbiddenEmptyNext
            foreach ($item in $r.stats.forbiddenEmptyNext) { outText "<@Cyan>  $($item.path)" }
        }
        if ($r.stats.usageRootPrefix.Count -gt 0) {
            outText $text.usageRootPrefix
            foreach ($item in $r.stats.usageRootPrefix) { outText "<@Cyan>  $($item.path)" }
        }
    }
}

if ($completedFiles -gt 0) {
    Write-Host
    foreach ($r in $completeResults) {
        $targetShortPath = "$($r.completion)/$($r.lang).json"
        $translated = $r.translated
        $total = $r.total
        $rate = $r.rate
        outText $text.langHeaderComplete
    }
}
