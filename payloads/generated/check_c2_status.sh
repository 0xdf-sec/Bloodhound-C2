#!/data/data/com.termux/files/usr/bin/bash

# Check C2 server status and database health

C2="http://{C2_HOST}:{C2_PORT}"

echo "🔍 C2 Server Status Check"
echo "========================"

# Test 1: Basic connectivity
echo "1️⃣ Testing basic connectivity..."
response=$(curl -s "$C2")
if [ -n "$response" ]; then
    echo "   ✅ C2 server is reachable"
else
    echo "   ❌ C2 server is not reachable"
    exit 1
fi

# Test 2: Check database health
echo "2️⃣ Checking database health..."
db_response=$(curl -s "$C2/debug/check-db")
if [ -n "$db_response" ]; then
    echo "   ✅ Database check response: $db_response"
else
    echo "   ❌ Database check failed"
fi

# Test 3: Check agents endpoint
echo "3️⃣ Checking agents endpoint..."
agents_response=$(curl -s "$C2/agents")
if [ -n "$agents_response" ]; then
    echo "   ✅ Agents endpoint working"
    echo "   📊 Current agents: $agents_response"
else
    echo "   ❌ Agents endpoint failed"
fi

# Test 4: Check API agents endpoint
echo "4️⃣ Checking API agents endpoint..."
api_agents_response=$(curl -s "$C2/api/agents")
if [ -n "$api_agents_response" ]; then
    echo "   ✅ API agents endpoint working"
    echo "   📊 API agents: $api_agents_response"
else
    echo "   ❌ API agents endpoint failed"
fi

# Test 5: Check recent activity
echo "5️⃣ Checking recent activity..."
activity_response=$(curl -s "$C2/api/recent-activity")
if [ -n "$activity_response" ]; then
    echo "   ✅ Recent activity endpoint working"
else
    echo "   ❌ Recent activity endpoint failed"
fi

echo ""
echo "🎯 Summary:"
echo "==========="
if [ -n "$agents_response" ] && [ "$agents_response" != "[]" ]; then
    echo "✅ Agents are visible in the system"
else
    echo "❌ No agents are visible - this is the problem!"
fi

echo ""
echo "💡 Next steps:"
echo "1. Run the debug agent script: ./debug_agent.sh"
echo "2. Check C2 server logs for database errors"
echo "3. Verify database file exists: c2.db"
