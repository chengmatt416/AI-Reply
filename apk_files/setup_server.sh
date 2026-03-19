#!/data/data/com.termux/files/usr/bin/bash
# ════════════════════════════════════════════════════════════════════
#  Server Setup and Start Script
#  Sets up and starts the llama-server for ChatAssistant
# ════════════════════════════════════════════════════════════════════
set -euo pipefail

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[0;33m'
BLU='\033[0;34m'; PRP='\033[0;35m'; CYN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GRN}[✓]${NC} $*"; }
warn() { echo -e "${YLW}[!]${NC} $*"; }
die()  { echo -e "${RED}[✗]${NC} $*"; exit 1; }
step() { echo -e "\n${PRP}━━━ $* ━━━${NC}"; }

PREFIX=/data/data/com.termux/files/usr
HOME_DIR=/data/data/com.termux/files/home
LLM_DIR=$HOME_DIR/llama.cpp
MODEL_DIR=$HOME_DIR/models
MODEL_FILE=$MODEL_DIR/gemma-2-2b-it-Q4_K_M.gguf
SERVER_BIN=$LLM_DIR/build/bin/llama-server

echo -e "${CYN}
╔══════════════════════════════════════════╗
║   Setting up llama-server               ║
╚══════════════════════════════════════════╝${NC}"

step "Installing dependencies"
pkg update -y -o Dpkg::Options::="--force-confold" 2>/dev/null || true
pkg install -y git cmake clang ninja python wget 2>/dev/null || die "Failed to install packages"
log "Dependencies installed"

step "Building llama.cpp"
if [ ! -f "$SERVER_BIN" ]; then
    if [ ! -d "$LLM_DIR/.git" ]; then
        warn "Cloning llama.cpp repository..."
        git clone --depth=1 https://github.com/ggerganov/llama.cpp "$LLM_DIR" || die "Failed to clone llama.cpp"
    fi

    cd "$LLM_DIR"
    warn "Compiling llama.cpp with optimizations (this will take several minutes)..."

    cmake -B build \
        -DGGML_VULKAN=OFF \
        -DGGML_OPENCL=OFF \
        -DCMAKE_BUILD_TYPE=Release \
        -DLLAMA_BUILD_SERVER=ON \
        -DGGML_NATIVE=OFF \
        -DCMAKE_C_FLAGS="-march=armv9-a+dotprod+i8mm" \
        -DCMAKE_CXX_FLAGS="-march=armv9-a+dotprod+i8mm" || die "CMake configuration failed"

    cmake --build build --config Release -j"$(nproc)" || die "Build failed"
    log "llama.cpp compiled successfully"
else
    log "llama-server already built"
fi

step "Downloading Gemma 2B model"
mkdir -p "$MODEL_DIR"
if [ ! -f "$MODEL_FILE" ]; then
    warn "Downloading Gemma 2B Q4_K_M model (~1.6GB, this will take time)..."
    wget -q --show-progress \
        "https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf" \
        -O "$MODEL_FILE" || {
        warn "Direct download failed, trying alternative method..."
        pip3 install -q huggingface_hub 2>/dev/null || true
        python3 -c "
from huggingface_hub import hf_hub_download
hf_hub_download(
    repo_id='bartowski/gemma-2-2b-it-GGUF',
    filename='gemma-2-2b-it-Q4_K_M.gguf',
    local_dir='$MODEL_DIR'
)
print('Model downloaded successfully')
" || die "Failed to download model"
    }
    log "Model downloaded"
else
    log "Model already exists"
fi

step "Creating server startup script"
cat > "$HOME_DIR/start_llm.sh" << LLMSH
#!/data/data/com.termux/files/usr/bin/bash
MODEL="$MODEL_FILE"
SERVER="$SERVER_BIN"

if [ ! -f "\$MODEL" ]; then
    echo "❌ Model not found: \$MODEL"
    exit 1
fi

if [ ! -f "\$SERVER" ]; then
    echo "❌ Server binary not found: \$SERVER"
    exit 1
fi

echo "🚀 Starting llama-server (Gemma 2B Q4_K_M)..."
echo "📡 Server will be available at http://127.0.0.1:8080"
echo "Press Ctrl+C to stop"

exec "\$SERVER" \\
    -m "\$MODEL" \\
    --host 127.0.0.1 \\
    --port 8080 \\
    -c 2048 \\
    --threads 6 \\
    -b 256 \\
    --chat-template gemma \\
    --log-disable
LLMSH
chmod +x "$HOME_DIR/start_llm.sh"
log "Startup script created: ~/start_llm.sh"

step "Setting up auto-start on boot (optional)"
mkdir -p "$HOME_DIR/.termux/boot"
cat > "$HOME_DIR/.termux/boot/start_assistant.sh" << BOOT
#!/data/data/com.termux/files/usr/bin/bash
sleep 10
termux-wake-lock
bash $HOME_DIR/start_llm.sh &
BOOT
chmod +x "$HOME_DIR/.termux/boot/start_assistant.sh"
log "Auto-start configured (requires Termux:Boot app)"

step "Starting llama-server"
echo -e "${YLW}Starting server in background...${NC}"

# Kill any existing server
pkill -f llama-server 2>/dev/null || true
sleep 1

# Start server in background
bash "$HOME_DIR/start_llm.sh" > "$HOME_DIR/llama_server.log" 2>&1 &
SERVER_PID=$!
echo "$SERVER_PID" > "$HOME_DIR/llama_server.pid"

echo "Waiting for server to start..."
for i in {1..30}; do
    if curl -s http://127.0.0.1:8080/health > /dev/null 2>&1; then
        log "Server started successfully (PID: $SERVER_PID)"
        log "Server log: ~/llama_server.log"
        break
    fi
    if [ $i -eq 30 ]; then
        die "Server failed to start. Check log: cat ~/llama_server.log"
    fi
    echo -n "."
    sleep 1
done

echo -e "
${GRN}╔════════════════════════════════════════════╗
║   ✅ Server Setup Complete!                ║
╠════════════════════════════════════════════╣
║  Server URL: http://127.0.0.1:8080        ║
║  Model: Gemma 2B Q4_K_M                    ║
║  PID: $SERVER_PID                             ║
║                                            ║
║  Commands:                                 ║
║  • Start: bash ~/start_llm.sh              ║
║  • Stop: kill \$(cat ~/llama_server.pid)    ║
║  • Logs: tail -f ~/llama_server.log        ║
║  • Test: bash ~/test_server.sh             ║
║                                            ║
║  Next: Run test_server.sh to verify!       ║
╚════════════════════════════════════════════╝${NC}"
