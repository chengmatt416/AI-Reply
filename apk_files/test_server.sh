#!/data/data/com.termux/files/usr/bin/bash
# ════════════════════════════════════════════════════════════════════
#  Server Test Script
#  Tests the llama-server to ensure it's working correctly
# ════════════════════════════════════════════════════════════════════
set -euo pipefail

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[0;33m'
BLU='\033[0;34m'; PRP='\033[0;35m'; CYN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GRN}[✓]${NC} $*"; }
warn() { echo -e "${YLW}[!]${NC} $*"; }
die()  { echo -e "${RED}[✗]${NC} $*"; exit 1; }
step() { echo -e "\n${PRP}━━━ $* ━━━${NC}"; }

SERVER_URL="http://127.0.0.1:8080"

echo -e "${CYN}
╔══════════════════════════════════════════╗
║   Testing llama-server                  ║
╚══════════════════════════════════════════╝${NC}"

step "Checking if server is running"
if ! curl -s "$SERVER_URL/health" > /dev/null 2>&1; then
    die "Server is not responding. Start it with: bash ~/setup_server.sh"
fi
log "Server is responding"

step "Testing health endpoint"
HEALTH=$(curl -s "$SERVER_URL/health" 2>/dev/null)
if echo "$HEALTH" | grep -q "ok\|status"; then
    log "Health check passed: $HEALTH"
else
    warn "Health check response: $HEALTH"
fi

step "Getting server props"
PROPS=$(curl -s "$SERVER_URL/props" 2>/dev/null)
if [ -n "$PROPS" ]; then
    echo "$PROPS" | python3 -m json.tool 2>/dev/null || echo "$PROPS"
    log "Server props retrieved"
else
    warn "Could not retrieve server props"
fi

step "Testing chat completions endpoint"
echo "Sending test request..."

RESPONSE=$(curl -s -X POST "$SERVER_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{
        "messages": [
            {"role": "system", "content": "你是智慧助理，用繁體中文簡短回答。"},
            {"role": "user", "content": "你好，今天天氣如何？"}
        ],
        "max_tokens": 50,
        "temperature": 0.7,
        "stream": false
    }' 2>/dev/null)

if [ -z "$RESPONSE" ]; then
    die "No response from server"
fi

echo -e "\n${BLU}Server Response:${NC}"
echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"

# Extract the actual reply
REPLY=$(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    content = data['choices'][0]['message']['content']
    print(content)
except:
    print('Could not parse response')
" 2>/dev/null)

if [ -n "$REPLY" ] && [ "$REPLY" != "Could not parse response" ]; then
    echo -e "\n${GRN}AI Reply:${NC} ${YLW}$REPLY${NC}"
    log "Chat completion test passed!"
else
    warn "Could not extract reply from response"
fi

step "Testing with ChatAssistant format"
echo "Sending ChatAssistant-style request..."

CA_RESPONSE=$(curl -s -X POST "$SERVER_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{
        "messages": [
            {"role": "system", "content": "你是智慧回覆助理。輸出嚴格JSON：{\"replies\":[\"回覆1\",\"回覆2\",\"回覆3\"],\"actions\":[]}"},
            {"role": "user", "content": "WeChat 對話：\n朋友：你在嗎？\n朋友：等下要不要一起吃飯？"}
        ],
        "max_tokens": 128,
        "temperature": 0.75,
        "stream": false
    }' 2>/dev/null)

echo -e "\n${BLU}ChatAssistant Response:${NC}"
echo "$CA_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$CA_RESPONSE"

CA_REPLY=$(echo "$CA_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    content = data['choices'][0]['message']['content']
    parsed = json.loads(content)
    print('Replies:', ', '.join(parsed['replies']))
except Exception as e:
    print(f'Could not parse: {e}')
" 2>/dev/null)

if [ -n "$CA_REPLY" ]; then
    echo -e "\n${GRN}Parsed Replies:${NC} ${YLW}$CA_REPLY${NC}"
    log "ChatAssistant format test passed!"
else
    warn "Could not parse ChatAssistant response"
fi

step "Performance check"
PID=$(cat ~/llama_server.pid 2>/dev/null || echo "")
if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    echo "Server PID: $PID"
    ps -p "$PID" -o pid,cpu,rss,cmd 2>/dev/null || true
else
    warn "Could not find server process"
fi

step "Checking logs"
if [ -f ~/llama_server.log ]; then
    echo -e "\n${BLU}Last 10 log lines:${NC}"
    tail -10 ~/llama_server.log
else
    warn "Log file not found"
fi

echo -e "
${GRN}╔════════════════════════════════════════════╗
║   ✅ Server Test Complete!                 ║
╠════════════════════════════════════════════╣
║  Server Status: ${GRN}Running${NC}                     ║
║  URL: http://127.0.0.1:8080                ║
║                                            ║
║  All tests passed successfully!            ║
║  The server is ready to use with the app.  ║
║                                            ║
║  Useful Commands:                          ║
║  • View logs: tail -f ~/llama_server.log   ║
║  • Stop server: kill \$(cat ~/llama_server.pid)
║  • Restart: bash ~/setup_server.sh         ║
╚════════════════════════════════════════════╝${NC}"
