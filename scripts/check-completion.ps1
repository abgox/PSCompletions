#Requires -Version 7.0

if (-not $env:GITHUB_ACTIONS) {
    throw 'It is a script for workflow'
}

function Add-GitHubLabel {
    param(
        [ValidateNotNullOrEmpty()]
        [String[]]$Label
    )

    Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/issues/$pr/labels" -Headers $headers -Method Post -Body (@{ labels = $Label } | ConvertTo-Json) -ContentType 'application/json'
}

function Remove-GitHubLabel {
    param(
        [ValidateNotNullOrEmpty()]
        [string[]]$Label
    )

    foreach ($name in $Label) {
        $encoded = [uri]::EscapeDataString($name)
        try {
            Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/issues/$pr/labels/$encoded" -Headers $headers -Method Delete
        }
        catch {
            if ($_.Exception.Response.StatusCode -ne [System.Net.HttpStatusCode]::NotFound) {
                throw
            }
        }
    }
}

$repo = $env:REPO
$pr = $env:PR_NUMBER
$marker = $env:MARKER
$headers = @{
    Authorization = "Bearer $env:GITHUB_TOKEN"
    Accept        = 'application/vnd.github.v3+json'
}

# 获取 PR 变更文件
$page = 1
$files = @()
$api = "https://api.github.com/repos/$repo/pulls/$pr/files?per_page=100"

while ($true) {
    $res = Invoke-RestMethod -Uri "$api&page=$page" -Headers $headers
    if (-not $res) { break }
    $files += $res
    if ($res.Count -lt 100) { break }
    $page++
}

# 扫描补全相关文件（language/*.json、config.json、hooks.ps1）
$changedCompletions = @()
$hasTemplate = $false

foreach ($file in $files) {
    $fn = $file.filename
    if ($fn -notmatch '^completions/([^/]+)/(config\.json|hooks\.ps1|language/.+\.json)$') {
        continue
    }
    $completion = $Matches[1]
    if ($completion -notin $changedCompletions) {
        $changedCompletions += $completion
    }

    if ($file.status -in @('added', 'modified', 'renamed')) {
        $localPath = [System.IO.Path]::Combine($PSScriptRoot, '..', $fn)
        if (Test-Path -LiteralPath $localPath) {
            $content = Get-Content -LiteralPath $localPath -Raw
            if ($content -like '*{{*') {
                $hasTemplate = $true
            }
        }
    }
}

$results = @()
$hasIssues = $false

if ($changedCompletions.Count -eq 0) {
    $results = @(
        $marker,
        '',
        '没有补全文件修改。 | No completion files modified.'
    )
}
else {
    $enFile = [System.IO.Path]::Combine($PSScriptRoot, 'result-validation-en.md')
    $zhFile = [System.IO.Path]::Combine($PSScriptRoot, 'result-validation-zh.md')

    $validationResults = & $PSScriptRoot\validate-completion.ps1 @($changedCompletions) -Lang en-US -OutFile $enFile
    $null = & $PSScriptRoot\validate-completion.ps1 @($changedCompletions) -Lang zh-CN -OutFile $zhFile

    $hasIssues = @($validationResults | Where-Object { $_.hasIssues }).Count -gt 0

    $jsonChanges = git diff --name-only -- 'completions/' | Where-Object { $_ -match '\.json$' }

    $results = @(
        $marker,
        '',
        '## 补全检查结果 | Completion Validation',
        ''
    )

    if (Test-Path -LiteralPath $zhFile) {
        $results += @(
            '',
            '<details>',
            '<summary>中文版</summary>',
            ''
        )
        $results += (Get-Content -LiteralPath $zhFile -Raw -ErrorAction SilentlyContinue)
        $results += @(
            '',
            '</details>'
        )
    }
    if (Test-Path -LiteralPath $enFile) {
        $results += @(
            '',
            '<details>',
            '<summary>English</summary>',
            ''
        )
        $results += (Get-Content -LiteralPath $enFile -Raw -ErrorAction SilentlyContinue)
        $results += @(
            '',
            '</details>'
        )
    }

    # 警告：需要排序
    if ($jsonChanges) {
        $results += @(
            '',
            '> [!WARNING]',
            '>',
            '> Please run it to sort and compare JSON, then commit the changes.',
            '>',
            '> ```powershell',
            '> .\scripts\compare-json.ps1',
            '> ```',
            ''
        )
    }

    # 警告：模板表达式需人工复核
    if ($hasTemplate) {
        $results += @(
            '',
            '> [!WARNING]',
            '>',
            '> - Some completions contain template expressions (`{{ xxx }}`) that are evaluated at runtime.',
            '> - Please review them carefully before merging.'
            ''
        )
    }
}

$results | Out-File -FilePath ([System.IO.Path]::Combine($PSScriptRoot, '..', 'result.md')) -Encoding utf8

$labels = [ordered]@{
    'check-failed'           = $hasIssues
    'security-review-needed' = $hasTemplate
}

$add_labels = @()
$rm_labels = @()

$labels.Keys | ForEach-Object { if ($labels.$_) { $add_labels += $_ } else { $rm_labels += $_ } }

if ($add_labels) { Add-GitHubLabel $add_labels }
if ($rm_labels) { Remove-GitHubLabel $rm_labels }
