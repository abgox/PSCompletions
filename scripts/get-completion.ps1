param(
    [Parameter(Mandatory = $true)]
    [string]$Prefix,
    [string]$OutFile
)

function Get-CompletionItem {
    param (
        [string]$Prefix,
        [switch]$ExcludeOptions
    )
    $completions = (TabExpansion2 $Prefix).CompletionMatches | ForEach-Object {
        [ordered]@{
            name = $_.CompletionText.Trim()
            tip  = , $_.ToolTip
        }
    }
    return , $completions
}

$out = Get-CompletionItem -Prefix $Prefix | ConvertTo-Json

if ($OutFile) {
    $out | Out-File -FilePath $OutFile -Encoding utf8
    Write-Host "Completion items saved to $OutFile"
    return
}

$out | Set-Clipboard
Write-Host "Completion items copied to clipboard"
