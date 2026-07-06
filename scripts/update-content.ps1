#Requires -Version 7.0

Set-StrictMode -Off

$textPath = "$PSScriptRoot/language/$PSCulture.json"
if (-not (Test-Path $textPath)) {
    $textPath = "$PSScriptRoot/language/en-US.json"
}
$text = Get-Content -Path $textPath -Encoding utf8 | ConvertFrom-Json

if (!$PSCompletions) { . $PSScriptRoot\..\module\PSCompletions\PSCompletions.ps1 }

function Get-StringHash {
    param(
        [Parameter(Mandatory)]
        [string]$Directory
    )

    if (-not (Test-Path $Directory)) { return }

    $files = Get-ChildItem -Path $Directory -File -Recurse | Sort-Object -Property FullName
    if (-not $files) { return }

    $sb = [System.Text.StringBuilder]::new()
    foreach ($file in $files) {
        [void]$sb.Append((Get-Content -Path $file.FullName -Raw -Encoding utf8))
    }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($sb.ToString())
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha256.ComputeHash($bytes)

    ($hashBytes | ForEach-Object -Process { $_.ToString('x2') }) -join ''
}

function Format-LanguageInfo {
    param(
        [string]$Name,
        [array]$LangList
    )

    $baseLang = $LangList[0]
    $langInfo = @("[**$baseLang**](/completions/$Name/language/$baseLang.json)")

    if ($LangList.Count -gt 1) {
        foreach ($lang in $LangList[1..($LangList.Count - 1)]) {
            if ($lang -in $jsonConfig.language) {
                $langInfo += "[**$lang**](/completions/$Name/language/$lang.json)"
            }
            else {
                $langInfo += "[**~~$lang~~**](/completions/$Name/language/$lang.json)"
            }
        }
    }
    return $langInfo
}

function New-MarkdownList {
    $contentEn = @('|Completion|Language|Description|', '|:-:|-|-|')
    $contentZh = @('|Completion|Language|Description|', '|:-:|-|-|')

    Get-ChildItem -Path "$PSScriptRoot/../completions" -Directory | ForEach-Object -Process {
        $infoEn = @()
        $infoZh = @()
        $completionData = @{}

        $jsonConfig = Get-Content -Path "$($_.FullName)/config.json" -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
        $langList = Get-ChildItem -Path "$($_.FullName)/language" -File | ForEach-Object -Process { $_.BaseName }

        foreach ($lang in $langList) {
            $completionData.$lang = Get-Content -Path "$($_.FullName)/language/$lang.json" -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
        }

        if ('zh-CN' -notin $completionData.Keys) { $completionData.'zh-CN' = $completionData.($langList[0]) }
        if ('en-US' -notin $completionData.Keys) { $completionData.'en-US' = $completionData.($langList[0]) }

        $infoEn += "[$($_.Name)]($($completionData.'en-US'.meta.url))"
        $infoZh += "[$($_.Name)]($($completionData.'zh-CN'.meta.url))"

        $langInfo = Format-LanguageInfo -Name $_.BaseName -LangList $langList
        $infoEn += $langInfo -join '<br>'
        $infoZh += $langInfo -join '<br>'

        $infoEn += $completionData.'en-US'.meta.description -join '<br>'
        $infoZh += $completionData.'zh-CN'.meta.description -join '<br>'

        $contentEn += '|' + ($infoEn -join '|') + '|'
        $contentZh += '|' + ($infoZh -join '|') + '|'
    }

    $contentEn += "`n<!-- prettier-ignore-end -->"
    $contentZh += "`n<!-- prettier-ignore-end -->"

    return @{
        'en-US' = $contentEn
        'zh-CN' = $contentZh
    }
}

function Update-ReadmeFile {
    param([string]$Language)

    $markdownLists = New-MarkdownList
    if ($Language -eq 'en-US') {
        $path = "$PSScriptRoot/../completions.md"
        $content = $markdownLists.'en-US'
    }
    else {
        $path = "$PSScriptRoot/../completions.zh-CN.md"
        $content = $markdownLists.'zh-CN'
    }

    function Get-StaticContent {
        param([string]$FilePath)
        $lines = Get-Content -Path $FilePath -Encoding utf8
        $match = $lines | Select-String -Pattern '<!-- prettier-ignore-start -->'
        if ($match) {
            $matchLineNumber = ([array]$match.LineNumber)[0]
            $lines | Select-Object -First $matchLineNumber
        }
    }

    (Get-StaticContent -FilePath $path) + $content | Out-File -FilePath $path -Encoding utf8 -Force
}

Update-ReadmeFile -Language 'en-US'
Update-ReadmeFile -Language 'zh-CN'

& $PSScriptRoot\sort-json.ps1

$path = "$PSScriptRoot\..\completions.json"
$old_info = Get-Content $path -Raw | ConvertFrom-Json -AsHashtable
$info = [ordered]@{
    list   = @()
    update = [ordered]@{}
    meta   = [ordered]@{}
}
Get-ChildItem "$PSScriptRoot\..\completions" -Directory | ForEach-Object {
    $completion = $_.Name
    $info.list += $completion
    $info.update[$completion] = Get-StringHash $_.FullName
    $info.meta[$completion] = [ordered]@{}
    Get-ChildItem "$($_.FullName)/language" -File | ForEach-Object {
        $info.meta.$completion[$_.BaseName] = Get-Content $_.FullName -Raw -Encoding utf8 | ConvertFrom-Json | Select-Object -ExpandProperty meta
    }
}

$info | ConvertTo-Json -Depth 10 | Out-File $path

if ($env:GITHUB_ACTIONS) {
    & $PSScriptRoot\push-change.ps1 -message 'chore: automatically update some content [skip ci]'
}
