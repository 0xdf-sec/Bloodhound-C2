$server = "10.0.0.207"
$port = "8084"
$hostname = $env:COMPUTERNAME

# Get IPv4 address (excluding loopback and virtual interfaces)
$ip = (Get-NetIPAddress -AddressFamily IPv4 |
       Where-Object { $_.IPAddress -notlike '127.*' -and $_.PrefixOrigin -ne 'WellKnown' } |
       Select-Object -First 1 -ExpandProperty IPAddress)

$uri = "http://${server}:${port}/register"
$body = @{
  hostname = $hostname
  os = "Windows"
  ip = $ip
} | ConvertTo-Json

Invoke-RestMethod -Uri $uri -Method Post -Body $body -ContentType "application/json"
