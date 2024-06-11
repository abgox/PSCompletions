function generate_list {
    $content_EN = @()
    $content_CN = @()
    Get-ChildItem "$PSScriptRoot\..\completions" | ForEach-Object {
        $info_EN = @()
        $info_CN = @()
        $completion = @{}
        $json_config = Get-Content "$($_.FullName)/config.json" -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable

        $lang_list = Get-ChildItem "$($_.FullName)/language" | ForEach-Object { $_.BaseName }
        foreach ($lang in $lang_list) {
            $completion.$lang = Get-Content "$($_.FullName)/language/$($lang).json" -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
        }
        if ("zh-CN" -notin $completion.Keys) {
            $completion."zh-CN" = $completion.($lang_list[0])
        }
        if ("en-US" -notin $completion.Keys) {
            $completion."en-US" = $completion.($lang_list[0])
        }
        if (!$completion."en-US".info) { $completion."en-US".info = $completion.($lang_list[0]).info }
        if (!$completion."zh-CN".info) { $completion."zh-CN".info = $completion.($lang_list[0]).info }

        # Completion
        ## EN
        if ($json_config.alias) {
            $info_EN += "[$($_.Name)($($json_config.alias))]($($completion."en-US".info.completion_info.url))"
        }
        else {
            $info_EN += "[$($_.Name)]($($completion."en-US".info.completion_info.url))"
        }
        ## CN
        if ($json_config.alias) {
            $info_CN += "[$($_.Name)($($json_config.alias))]($($completion."zh-CN".info.completion_info.url))"
        }
        else {
            $info_CN += "[$($_.Name)]($($completion."zh-CN".info.completion_info.url))"
        }

        # Language
        function handle_language($lang_list = $lang_list) {
            function ConvertTo-FlatHashtable {
                param (
                    [Parameter(Mandatory = $true)][hashtable]$InputHashtable,
                    [string]$Prefix = ""
                )
                $flatHashtable = @{}

                foreach ($key in $InputHashtable.Keys) {
                    $fullKey = if ($Prefix) { "$Prefix.$key" } else { $key }

                    if ($InputHashtable[$key] -is [hashtable]) {
                        $nestedHashtable = ConvertTo-FlatHashtable -InputHashtable $InputHashtable[$key] -Prefix $fullKey
                        foreach ($nestedKey in $nestedHashtable.Keys) {
                            $flatHashtable[$nestedKey] = $nestedHashtable[$nestedKey]
                        }
                    }
                    elseif ($InputHashtable[$key] -is [array]) {
                        $array = $InputHashtable[$key]
                        if ($array -and $array[0] -is [hashtable]) {
                            for ($i = 0; $i -lt $array.Count; $i++) {
                                $element = $array[$i]
                                $elementPrefix = if ($element.ContainsKey("name")) { "$fullKey`['{name:`"$($element.name)`"}']" } else { "$fullKey[$i]" }
                                $nestedHashtable = ConvertTo-FlatHashtable -InputHashtable $element -Prefix $elementPrefix
                                foreach ($nestedKey in $nestedHashtable.Keys) {
                                    $flatHashtable[$nestedKey] = $nestedHashtable[$nestedKey]
                                }
                            }
                        }
                        else {
                            $flatHashtable[$fullKey] = ($array -join ",")
                        }
                    }
                    else {
                        $flatHashtable[$fullKey] = $InputHashtable[$key]
                    }
                }
                return $flatHashtable
            }
            function Compare-JsonProperties {
                param (
                    [Parameter(Mandatory = $true)][hashtable]$hashTableEN,
                    [Parameter(Mandatory = $true)][hashtable]$hashTableCN
                )

                $flatEN = ConvertTo-FlatHashtable -InputHashtable $hashTableEN
                $flatCN = ConvertTo-FlatHashtable -InputHashtable $hashTableCN

                $missingProperties = $flatEN.Keys | Where-Object { $_ -notin $flatCN.Keys }
                $extraProperties = $flatCN.Keys | Where-Object { $_ -notin $flatEN.Keys }
                $totalProperties = $flatEN.Count
                $missingCount = $missingProperties.Count
                $extraCount = $extraProperties.Count
                $completionPercentage = ((($totalProperties - $missingCount) + $extraCount) / $totalProperties) * 100

                return @{
                    MissingProperties    = $missingProperties
                    ExtraProperties      = $extraProperties
                    CompletionPercentage = [math]::Round($completionPercentage, 2)
                }
            }

            $json1 = Get-Content -Path "$($_.FullName)/language/$($lang_list[0]).json" -Raw | ConvertFrom-Json -Depth 100
            $hashTableEN = $json1 | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable -Depth 100

            function get_percentage($lang) {
                $json2 = Get-Content -Path "$($_.FullName)/language/$($lang).json" -Raw | ConvertFrom-Json -Depth 100
                # 将 JSON 对象转换为哈希表
                $hashTableCN = $json2 | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable -Depth 100

                # 比较属性并计算完成进度
                $result = Compare-JsonProperties -hashTableEN $hashTableEN -hashTableCN $hashTableCN
                return $result.CompletionPercentage
            }
            $lang_info = @("``$($lang_list[0])``")
            if ($lang_list.Count -gt 1) {
                foreach ($lang in $lang_list[1..($lang_list.Count - 1)]) {
                    $percentage = get_percentage $lang
                    if ($lang -in $json_config.language) {
                        $lang_info += "``$($lang)($($percentage)%)``"
                    }
                    else {
                        $lang_info += "~~``$($lang)($($percentage)%)``~~"
                    }
                }
            }
            return $lang_info
        }

        $lang_info = handle_language
        $info_EN += $lang_info -join '<br>'
        $info_CN += $lang_info -join '<br>'

        # Description
        ## EN
        $info_EN += ($completion."en-US".info.completion_info.description -join ' ') -replace '\n', '<br>'
        ## CN
        $info_CN += ($completion."zh-CN".info.completion_info.description -join ' ') -replace '\n', '<br>'

        $content_EN += "|" + ($info_EN -join "|") + "|"
        $content_CN += "|" + ($info_CN -join "|") + "|"
    }

    $footer = '|...|...&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;|...|'

    $content_EN += $footer
    $content_CN += $footer

    return @{
        "en-US" = $content_EN
        "zh-CN" = $content_CN
    }
}

function handle($lang) {
    $content = generate_list
    if ($lang -eq "en-US") {
        $path = "$PSScriptRoot\..\README.md"
        $content = $content."en-US"
    }
    else {
        $path = "$PSScriptRoot\..\README-CN.md"
        $content = $content."zh-CN"
    }
    function get_static_content($path) {
        $content = Get-Content -Path $path -Encoding UTF8

        $match = $content | Select-String -Pattern "\|:-:\|-\|-\|"

        if ($match) {
            $matchLineNumber = ([array]$match.LineNumber)[0]
            $result = $content | Select-Object -First $matchLineNumber
            $result
        }
    }
    (get_static_content $path) + $content | Out-File $path -Encoding UTF8 -Force
}

handle "en-US"
handle "zh-CN"
