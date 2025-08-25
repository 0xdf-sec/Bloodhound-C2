#!/data/data/com.termux/files/usr/bin/bash

# Test script to check if agent stays online

C2="http://{C2_HOST}:{C2_PORT}"
HOSTNAME="SM-S918W"  # Your actual agent hostname

echo "🔍 Testing Agent Status: $HOSTNAME"
echo "================================"

# Check initial status
echo "1️⃣ Initial agent status..."
initial_status=$(curl -s "$C2/agents" | grep -o '"status":"[^"]*"' | head -1)
echo "   Status: $initial_status"

# Wait and check again
echo "2️⃣ Waiting 15 seconds..."
sleep 15

echo "3️⃣ Checking status again..."
second_status=$(curl -s "$C2/agents" | grep -o '"status":"[^"]*"' | head -1)
echo "   Status: $second_status"

# Check if agent is still visible
echo "4️⃣ Checking if agent is still visible..."
agents_response=$(curl -s "$C2/agents")
if echo "$agents_response" | grep -q "$HOSTNAME"; then
    echo "   ✅ Agent is still visible in system"
else
    echo "   ❌ Agent disappeared from system"
fi

echo ""
echo "🎯 Summary:"
if [ "$initial_status" = "$second_status" ] && [ "$initial_status" = '"status":"Online"' ]; then
    echo "✅ Agent is staying online consistently"
elif [ "$initial_status" != "$second_status" ]; then
    echo "⚠️  Agent status changed: $initial_status → $second_status"
else
    echo "❌ Agent is not staying online"
fi
