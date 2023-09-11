function _psc_replace($data) {
    $data = $data -join ''
    $pattern = '\{\{(.*?(\})*)(?=\}\})\}\}'
    $matches = [regex]::Matches($data, $pattern)
    foreach ($match in $matches) {
        $data = $data.Replace($match.Value, (Invoke-Expression $match.Groups[1].Value))
    }
    if ($data -match $pattern) { _psc_replace $data }
    else { return $data }
}
