function _psc_replace($data){
    $p1 = '\@\{\{([^}]+)\}\}'
    $matches = [regex]::Matches($data, $p1)
    foreach ($match in $matches) {
        $tempate= $match.Groups[1].Value -split ';'
        foreach($__t in $tempate){
            $cmds = $__t -split '='
            Set-Variable -Name ($cmds[0].Replace('$','')) -Value (Invoke-Expression $cmds[1])
            $data = $data.Replace($match.Value, '')
        }
    }
    $p2 = '\{\{([^}]+)\}\}'
    $matches = [regex]::Matches($data, $p2)
    foreach ($match in $matches) {
        $data = $data.Replace($match.Value, (Invoke-Expression $match.Groups[1].Value))
    }
    return $data
}
