#Requires -Version 7.0

Set-StrictMode -Off

$textPath = "$PSScriptRoot/language/$PSCulture.json"
if (!(Test-Path $textPath)) {
    $textPath = "$PSScriptRoot/language/en-US.json"
}
$text = Get-Content -Path $textPath -Encoding utf8 | ConvertFrom-Json

if (!$PSCompletions) {
    . $PSScriptRoot\..\module\PSCompletions\core.ps1
}

function Get-StringHash {
    param(
        [Parameter(Mandatory)]
        [string]$dir
    )

    if (-not (Test-Path $dir)) {
        return
    }

    $files = Get-ChildItem $dir -File -Recurse | Sort-Object FullName

    if (-not $files) {
        return
    }

    $str = ''
    foreach ($file in $files) {
        $str += Get-Content $file.FullName -Raw -Encoding utf8
    }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($str)

    # SHA256
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha.ComputeHash($bytes)

    # hex
    ($hashBytes | ForEach-Object { $_.ToString('x2') }) -join ''
}

function Compare-JsonProperty {
    param (
        [string]$diffJson,
        [string]$baseJson,
        [switch]$ReturnRate
    )

    # 读取 JSON 文件
    $diffContent = Get-Content -Path $diffJson -Raw | ConvertFrom-Json -AsHashtable
    $baseContent = Get-Content -Path $baseJson -Raw | ConvertFrom-Json -AsHashtable

    $is_psc = $diffJson -match '.*[\/\\]completions[\/\\]psc[\/\\]language[\/\\].*'

    # 统计
    $count = @{
        totalTips        = 0   # 总的 tip 数量

        diffList         = @() # 不同的属性值或类型
        untranslatedList = @() # 未翻译的
    }

    function noTranslated() {
        param($diffStr, $baseStr)
        # XXX: 以中文为例，可以通过判断是否存在中文字符
        # 直接判断是否相等，目前也可用

        # psc 有些特殊，不使用 replace_content
        if ($is_psc) {
            return $diffStr -ceq $baseStr
        }

        try {
            $json = $diffContent
            $info = $diffContent.info
            $diff = $PSCompletions.replace_content($diffStr)
        }
        catch {
            Write-Host "Error in $(Resolve-Path $diffJson)" -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor Red
            Write-Host $diffStr
            exit 1
        }

        try {
            $json = $baseContent
            $info = $baseContent.info
            $base = $PSCompletions.replace_content($baseStr)
        }
        catch {
            Write-Host "Error in $(Resolve-Path $baseJson)" -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor Red
            Write-Host $baseStr
            exit 1
        }
        return $diff -ceq $base
    }

    function isExist {
        param($v)
        # XXX: 在 PowerShell 中，对于空数组，以下两种判断都返回空，而非布尔。空又会被当做 false
        # @() -eq $null # 返回空，也就是 false
        # @() -ne $null # 返回空，也就是 false
        # 因此，如果它的类型是一个数组，就应该认为它存在
        return $v -is [array] -or $v -ne $null
    }

    # 定义递归函数以遍历
    function traverseArr {
        param (
            [array]$diffArr, # 比对
            [array]$baseArr, # 基准
            [string]$pos = ''
        )
        $baseIndex = 0
        $diffIndex = 0

        while ($baseIndex -lt $baseArr.Count -or $diffIndex -lt $diffArr.Count) {
            $baseItem = if ($baseIndex -lt $baseArr.Count) { $baseArr[$baseIndex] } else { $null }
            $diffItem = if ($diffIndex -lt $diffArr.Count) { $diffArr[$diffIndex] } else { $null }

            # name
            $isDiff = $false
            if ($baseItem.name) {
                if ($diffItem.name) {
                    if ($baseItem.name -cne $diffItem.name) {
                        $isDiff = $true
                    }
                }
                else {
                    $isDiff = $true
                }

            }
            else {
                if ($diffItem.name) {
                    $isDiff = $true
                }
            }
            if ($isDiff) {
                $count.diffList += @{
                    base = $baseItem.name
                    diff = $diffItem.name
                    pos  = "$pos[$baseIndex].name"
                }
                return
            }

            # alias
            $isDiff = $false
            if ($baseItem.alias) {
                if ($diffItem.alias) {
                    if (Compare-Object $baseItem.alias $diffItem.alias -CaseSensitive) {
                        $isDiff = $true
                    }
                }
                else {
                    $isDiff = $true
                }
            }
            else {
                if ($diffItem.alias) {
                    $isDiff = $true
                }
            }
            if ($isDiff) {
                $count.diffList += @{
                    name = $baseItem.name
                    base = $baseItem.alias -join ' '
                    diff = $diffItem.alias -join ' '
                    pos  = "$pos[$baseIndex].alias"
                }
                return
            }

            # hide
            $isDiff = $false
            if ($null -ne $baseItem.hide) {
                if ($null -ne $diffItem.hide) {
                    if ($baseItem.hide -ne $diffItem.hide) {
                        $isDiff = $true
                    }
                }
                else {
                    $isDiff = $true
                }
            }
            else {
                if ($null -ne $diffItem.hide) {
                    $isDiff = $true
                }
            }
            if ($isDiff) {
                $count.diffList += @{
                    name = $baseItem.name
                    base = $baseItem.hide
                    diff = $diffItem.hide
                    pos  = "$pos[$baseIndex].hide"
                }
                return
            }

            # next
            # options
            foreach ($item in @('next', 'options')) {
                $isDiff = $false
                if (isExist $baseItem.$item) {
                    if (isExist $diffItem.$item) {
                        $baseType = $baseItem.$item.GetType().Name
                        $diffType = $diffItem.$item.GetType().Name
                        if ($baseType -ne $diffType) {
                            $isDiff = $true
                        }
                    }
                    else {
                        $isDiff = $true
                    }
                }
                else {
                    if (isExist $diffItem.$item) {
                        $isDiff = $true
                    }
                }
                if ($isDiff) {
                    $count.diffList += @{
                        name = $baseItem.name
                        base = if ($baseItem.$item -is [array] -and $baseItem.$item.Count -eq 0) { '[]' }else { $baseItem.$item }
                        diff = if ($diffItem.$item -is [array] -and $diffItem.$item.Count -eq 0) { '[]' }else { $diffItem.$item }
                        pos  = "$pos[$baseIndex].$item"
                    }
                    return
                }

                if ($baseItem.$item -is [array] -and $diffItem.$item -is [array]) {
                    traverseArr $diffItem.$item $baseItem.$item "$pos[$baseIndex].$item"
                }
            }

            # value
            $isDiff = $false
            if ($null -ne $baseItem.value) {
                if ($null -ne $diffItem.value) {
                    if ($baseItem.value -cne $diffItem.value) {
                        $isDiff = $true
                    }
                }
                else {
                    $isDiff = $true
                }
            }
            else {
                if ($null -ne $diffItem.value) {
                    $isDiff = $true
                }
            }
            if ($isDiff) {
                $count.diffList += @{
                    name = $baseItem.name
                    base = $baseItem.value
                    diff = $diffItem.value
                    pos  = "$pos[$baseIndex].value"
                }
                return
            }

            # values
            $isDiff = $false
            if (isExist $baseItem['values']) {
                if (isExist $diffItem['values']) {
                    if (Compare-Object $baseItem['values'] $diffItem['values'] -CaseSensitive) {
                        $isDiff = $true
                    }
                }
                else {
                    $isDiff = $true
                }
            }
            else {
                if (isExist $diffItem['values']) {
                    $isDiff = $true
                }
            }
            if ($isDiff) {
                $count.diffList += @{
                    name = $baseItem.name
                    base = $baseItem['values'] -join ' '
                    diff = $diffItem['values'] -join ' '
                    pos  = "$pos[$baseIndex].values"
                }
                return
            }

            # tip
            $isDiff = $false
            if ($baseItem.tip) {
                $count.totalTips++
                if ($diffItem.tip) {
                    if (noTranslated $diffItem.tip $baseItem.tip) {
                        $count.untranslatedList += @{
                            name  = $diffItem.name
                            value = "`n" + ($diffItem.tip -join "`n")
                            pos   = "$pos[$baseIndex].tip"
                        }
                    }
                }
                else {
                    $isDiff = $true
                }
            }
            else {
                if ($diffItem.tip) {
                    $isDiff = $true
                }
            }
            if ($isDiff) {
                $count.diffList += @{
                    name = $baseItem.name
                    base = "`n" + ($baseItem.tip -join "`n")
                    diff = "`n" + ($diffItem.tip -join "`n")
                    pos  = "$pos[$baseIndex].tip"
                }
                return
            }

            $baseIndex++
            $diffIndex++
        }
    }

    foreach ($item in @('root', 'options', 'common_options', 'config')) {
        if ($count.diffList.Count -gt 0) {
            break
        }
        $isDiff = $false
        if ($baseContent.$item.Count) {
            if ($diffContent.$item.Count) {
                traverseArr $diffContent.$item $baseContent.$item $item
            }
            else {
                $isDiff = $true
            }
        }
        else {
            if ($diffContent.$item.Count) {
                $isDiff = $true
            }
        }
        if ($isDiff) {
            $count.diffList += @{
                base = if ($baseContent.$item.Count) { '[ ... ]' }
                diff = if ($diffContent.$item.Count) { '[ ... ]' }
                pos  = $item
            }
            break
        }
    }

    if ($baseContent.info) {
        function traverseObj {
            param($diffObj, $baseObj, $pos)

            if ($null -eq $baseObj -or $null -eq $diffObj) {
                $count.diffList += @{
                    base = if ($null -ne $baseObj) { '{ ... }' }
                    diff = if ($null -ne $diffObj) { '{ ... }' }
                    pos  = $pos
                }
                return
            }

            $keys = @() + $diffObj.Keys + $baseObj.Keys | Sort-Object -Unique

            foreach ($key in $keys) {
                $isDiff = $false
                if (isExist $baseObj[$key]) {
                    if (isExist $diffObj[$key]) {
                        $baseType = $baseObj[$key].GetType().Name
                        $diffType = $diffObj[$key].GetType().Name
                        if ($baseType -ne $diffType) {
                            $isDiff = $true
                        }
                        else {
                            switch ($baseObj[$key]) {
                                { $_ -is [string] -or $_ -is [array] } {
                                    $diffStr = $diffObj[$key] -join ' '
                                    $baseStr = $baseObj[$key] -join ' '
                                    if ($diffStr -match '^https?://.+') {
                                        continue
                                    }
                                    if (noTranslated $diffStr $baseStr) {
                                        $count.totalTips++
                                        $count.untranslatedList += @{
                                            name  = $key
                                            value = $diffObj[$key]
                                            pos   = "$pos.$key"
                                        }
                                    }
                                }
                                { $_ -is [int] -or $_ -is [bool] } {
                                    if ($baseObj[$key] -cne $diffObj[$key]) {
                                        $isDiff = $true
                                    }
                                }
                                # 对象
                                default {
                                    traverseObj $diffObj[$key] $baseObj[$key] "$pos.$key"
                                }
                            }
                        }
                    }
                    else {
                        $isDiff = $true
                    }
                }
                else {
                    if (isExist $diffObj[$key]) {
                        $isDiff = $true
                    }
                }
                if ($isDiff) {
                    $count.diffList += @{
                        base = $baseObj[$key]
                        diff = $diffObj[$key]
                        pos  = "$pos.$key"
                    }
                    return
                }
            }
        }
        traverseObj $diffContent.info $baseContent.info 'info'
    }
    if ($count.diffList.Count -gt 0) {
        $completionRate = 0.01
    }
    else {
        if ($count.totalTips -gt 0) {
            $completionRate = 100 - ($count.untranslatedList.Count / $count.totalTips) * 100
        }
        else {
            $completionRate = 100
        }
    }
    $completionRate = [Math]::Max([Math]::Round($completionRate, 2), 0.01)

    if ($ReturnRate) {
        return $completionRate
    }

    $baseShortPath = Split-Path $baseJson -Leaf
    $diffShortPath = Split-Path $diffJson -Leaf

    outText $text.progress

    if ($count.diffList -and 'diff' -in $Show) {
        outText $text.diffList.tip
        foreach ($item in $count.diffList) {
            $prop = if ($null -eq $item.name) { '' }else { " (name: $($item.name))" }
            outText ($text.pos + $prop)
            outText $text.diffList.base
            outText $text.diffList.diff
        }
        outText $text.hr
    }

    if ($count.untranslatedList -and 'untranslated' -in $Show) {
        outText $text.untranslatedList.tip
        foreach ($item in $count.untranslatedList) {
            $prop = if ($null -eq $item.name) { '' }else { " (name: $($item.name))" }
            outText ($text.pos + $prop)
            outText $text.value
        }
        outText $text.hr
    }
}

function handle_language {
    param(
        [string]$name,
        [array]$lang_list = $lang_list
    )
    function getCompletionRate {
        param($lang)
        Compare-JsonProperty "$($_.FullName)/language/$($lang).json" "$($_.FullName)/language/$($lang_list[0]).json" -ReturnRate
    }

    $lang_info = @("[**$($lang_list[0])**](/completions/$($name)/language/$($lang_list[0]).json)")
    if ($lang_list.Count -gt 1) {
        foreach ($lang in $lang_list[1..($lang_list.Count - 1)]) {
            $percentage = getCompletionRate $lang
            if ($lang -in $json_config.language) {
                $lang_info += "[**$($lang)($($percentage)%)**](/completions/$($name)/language/$($lang).json)"
            }
            else {
                $lang_info += "[**~~$($lang)($($percentage)%)~~**](/completions/$($name)/language/$($lang).json)"
            }
        }
    }
    return $lang_info
}

function generate_list {
    $content_EN = @('|Completion|Language|Description|', '|:-:|-|-|')
    $content_CN = @('|Completion|Language|Description|', '|:-:|-|-|')
    Get-ChildItem "$PSScriptRoot\..\completions" | ForEach-Object {
        $info_EN = @()
        $info_CN = @()
        $completion = @{}
        $json_config = Get-Content "$($_.FullName)/config.json" -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable

        $lang_list = Get-ChildItem "$($_.FullName)/language" | ForEach-Object { $_.BaseName }
        foreach ($lang in $lang_list) {
            $completion.$lang = Get-Content "$($_.FullName)/language/$($lang).json" -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
        }
        if ('zh-CN' -notin $completion.Keys) {
            $completion.'zh-CN' = $completion.($lang_list[0])
        }
        if ('en-US' -notin $completion.Keys) {
            $completion.'en-US' = $completion.($lang_list[0])
        }
        if (!$completion.'en-US'.info) { $completion.'en-US'.info = $completion.($lang_list[0]).info }
        if (!$completion.'zh-CN'.info) { $completion.'zh-CN'.info = $completion.($lang_list[0]).info }

        # Completion
        ## EN
        $info_EN += "[$($_.Name)]($($completion.'en-US'.meta.url))"

        ## CN
        $info_CN += "[$($_.Name)]($($completion.'zh-CN'.meta.url))"

        # Language
        $lang_info = handle_language $_.BaseName $lang_list
        $info_EN += $lang_info -join '<br>'
        $info_CN += $lang_info -join '<br>'

        # Description
        ## EN
        $info_EN += $completion.'en-US'.meta.description -join '<br>'
        ## CN
        $info_CN += $completion.'zh-CN'.meta.description -join '<br>'

        $content_EN += '|' + ($info_EN -join '|') + '|'
        $content_CN += '|' + ($info_CN -join '|') + '|'
    }

    $footer = '|...|...&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;|...|'

    $content_EN += $footer + "`n<!-- prettier-ignore-end -->"
    $content_CN += $footer + "`n<!-- prettier-ignore-end -->"

    return @{
        'en-US' = $content_EN
        'zh-CN' = $content_CN
    }
}

function update_readme($lang) {
    $content = generate_list
    if ($lang -eq 'en-US') {
        $path = "$PSScriptRoot\..\completions.md"
        $content = $content.'en-US'
    }
    else {
        $path = "$PSScriptRoot\..\completions.zh-CN.md"
        $content = $content.'zh-CN'
    }
    function get_static_content($path) {
        $content = Get-Content -Path $path -Encoding UTF8

        $match = $content | Select-String -Pattern '<!-- prettier-ignore-start -->'

        if ($match) {
            $matchLineNumber = ([array]$match.LineNumber)[0]
            $result = $content | Select-Object -First $matchLineNumber
            $result
        }
    }
    (get_static_content $path) + $content | Out-File $path -Encoding UTF8 -Force
}

update_readme 'en-US'
update_readme 'zh-CN'

& $PSScriptRoot\sort-completion.ps1

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

git -c core.safecrlf=false add -u

if (git status --porcelain) {
    git -c user.name="github-actions[bot]" -c user.email="41898282+github-actions[bot]@users.noreply.github.com" commit --no-gpg-sign -m 'chore: automatically update some content [skip ci]'
}
