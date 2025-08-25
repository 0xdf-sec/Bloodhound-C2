#!/data/data/com.termux/files/usr/bin/bash

# Android Termux Agent Management Script
# This script helps you manage the Android agent

AGENT_SCRIPT="android_termux_agent_fixed.sh"
PID_FILE="/data/data/com.termux/files/home/.agent.pid"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Android Termux Agent Manager${NC}"
echo "================================"

case "$1" in
    start)
        echo -e "${GREEN}Starting Android Termux Agent...${NC}"
        if [ -f "$PID_FILE" ]; then
            old_pid=$(cat "$PID_FILE")
            if kill -0 "$old_pid" 2>/dev/null; then
                echo -e "${YELLOW}Agent is already running with PID $old_pid${NC}"
                echo "Use './manage_android_agent.sh stop' to stop it first"
                exit 1
            else
                echo "Removing stale PID file..."
                rm -f "$PID_FILE"
            fi
        fi
        
        if [ -f "$AGENT_SCRIPT" ]; then
            chmod +x "$AGENT_SCRIPT"
            nohup ./"$AGENT_SCRIPT" > /dev/null 2>&1 &
            echo -e "${GREEN}Agent started in background${NC}"
            echo "Use './manage_android_agent.sh status' to check status"
        else
            echo -e "${RED}Error: $AGENT_SCRIPT not found${NC}"
            exit 1
        fi
        ;;
        
    stop)
        echo -e "${YELLOW}Stopping Android Termux Agent...${NC}"
        if [ -f "$PID_FILE" ]; then
            pid=$(cat "$PID_FILE")
            if kill -0 "$pid" 2>/dev/null; then
                echo "Stopping agent with PID $pid..."
                kill "$pid"
                sleep 2
                if kill -0 "$pid" 2>/dev/null; then
                    echo "Force killing agent..."
                    kill -9 "$pid"
                fi
                rm -f "$PID_FILE"
                echo -e "${GREEN}Agent stopped${NC}"
            else
                echo "Agent not running (stale PID file)"
                rm -f "$PID_FILE"
            fi
        else
            echo "No PID file found, trying to kill by process name..."
            pkill -f "$AGENT_SCRIPT" 2>/dev/null
            echo -e "${GREEN}Agent stopped${NC}"
        fi
        ;;
        
    restart)
        echo -e "${BLUE}Restarting Android Termux Agent...${NC}"
        ./manage_android_agent.sh stop
        sleep 2
        ./manage_android_agent.sh start
        ;;
        
    status)
        echo -e "${BLUE}Android Termux Agent Status${NC}"
        echo "=============================="
        if [ -f "$PID_FILE" ]; then
            pid=$(cat "$PID_FILE")
            if kill -0 "$pid" 2>/dev/null; then
                echo -e "${GREEN}✓ Agent is RUNNING${NC}"
                echo "PID: $pid"
                echo "Started: $(ps -o lstart= -p $pid 2>/dev/null || echo 'Unknown')"
                echo "Memory: $(ps -o rss= -p $pid 2>/dev/null | awk '{print $1/1024 " MB"}' || echo 'Unknown')"
            else
                echo -e "${RED}✗ Agent is NOT RUNNING (stale PID file)${NC}"
                echo "PID file exists but process is dead"
                rm -f "$PID_FILE"
            fi
        else
            echo -e "${RED}✗ Agent is NOT RUNNING${NC}"
            echo "No PID file found"
        fi
        
        # Check if process is running by name
        if pgrep -f "$AGENT_SCRIPT" >/dev/null; then
            echo -e "${GREEN}✓ Process found by name${NC}"
            pgrep -f "$AGENT_SCRIPT" | while read p; do
                echo "  PID $p: $(ps -o cmd= -p $p 2>/dev/null | head -c 50)..."
            done
        fi
        ;;
        
    logs)
        echo -e "${BLUE}Recent Agent Logs${NC}"
        echo "=================="
        if [ -f "/data/data/com.termux/files/home/.agent.log" ]; then
            tail -20 "/data/data/com.termux/files/home/.agent.log"
        else
            echo "No log file found"
        fi
        ;;
        
    killall)
        echo -e "${RED}Force killing ALL Android agent processes...${NC}"
        pkill -9 -f "$AGENT_SCRIPT" 2>/dev/null
        rm -f "$PID_FILE"
        echo -e "${GREEN}All agent processes killed${NC}"
        ;;
        
    *)
        echo "Usage: $0 {start|stop|restart|status|logs|killall}"
        echo ""
        echo "Commands:"
        echo "  start   - Start the Android Termux agent"
        echo "  stop    - Stop the agent gracefully"
        echo "  restart - Restart the agent"
        echo "  status  - Show agent status and info"
        echo "  logs    - Show recent logs"
        echo "  killall - Force kill all agent processes"
        echo ""
        echo "Examples:"
        echo "  ./manage_android_agent.sh start"
        echo "  ./manage_android_agent.sh stop"
        echo "  ./manage_android_agent.sh status"
        exit 1
        ;;
esac
