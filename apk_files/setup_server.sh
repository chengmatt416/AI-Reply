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
LOG_FILE=$HOME_DIR/llama_server.log

echo -e "${CYN}
╔══════════════════════════════════════════╗
║   Setting up llama-server               ║
╚══════════════════════════════════════════╝${NC}"

# ─── Pre-flight system checks ────────────────────────────────────────────────
step "Checking system environment"

ARCH=$(uname -m)
log "Architecture: $ARCH"
if [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "arm64" ]; then
    warn "Unexpected architecture '$ARCH'. This script is optimised for aarch64 (ARM64)."
fi

# Check for proot environment (PROOT_TMP_DIR is set by the proot runtime)
if [ -n "${PROOT_TMP_DIR:-}" ]; then
    PROOT_STATUS="proot environment detected"
else
    PROOT_STATUS="native Termux"
fi
log "Execution environment: $PROOT_STATUS"

# Check SELinux status (may restrict exec/mmap in some Android builds)
SELINUX_STATUS="unknown"
if command -v getenforce >/dev/null 2>&1; then
    SELINUX_STATUS=$(getenforce 2>/dev/null || echo "unknown")
elif [ -f /sys/fs/selinux/enforce ]; then
    RAW=$(cat /sys/fs/selinux/enforce 2>/dev/null || echo "")
    case "$RAW" in
        1) SELINUX_STATUS="Enforcing" ;;
        0) SELINUX_STATUS="Permissive" ;;
        *) SELINUX_STATUS="unknown" ;;
    esac
fi
log "SELinux: $SELINUX_STATUS"
if [ "$SELINUX_STATUS" = "Enforcing" ]; then
    warn "SELinux is Enforcing — this can block mmap/exec in Termux. If server fails, run: su -c setenforce 0"
fi

# Check available RAM (Q4_K_M Gemma 2B needs ~2.5 GB RSS; warn below 3 GB)
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)
AVAIL_RAM_KB=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)
TOTAL_RAM_MB=$(( TOTAL_RAM_KB / 1024 ))
AVAIL_RAM_MB=$(( AVAIL_RAM_KB / 1024 ))
log "RAM: ${AVAIL_RAM_MB} MB available / ${TOTAL_RAM_MB} MB total"
if [ "$TOTAL_RAM_MB" -lt 3000 ]; then
    warn "Total RAM is ${TOTAL_RAM_MB} MB. Gemma 2B Q4_K_M requires ~2.5 GB; the server may be killed by OOM."
    warn "Consider closing other apps or using a smaller model (e.g. Q2_K)."
fi

# Check number of available CPU threads
CPU_THREADS=$(nproc 2>/dev/null || echo 4)
log "CPU threads available: $CPU_THREADS"

log "System checks complete"

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

# ─── Verify runtime files before attempting to start ─────────────────────────
step "Verifying runtime files"

# Check server binary exists and is executable
if [ ! -f "$SERVER_BIN" ]; then
    die "Server binary not found: $SERVER_BIN — did the build succeed?"
fi
if [ ! -x "$SERVER_BIN" ]; then
    warn "Server binary is not executable; attempting chmod +x..."
    chmod +x "$SERVER_BIN" || die "Cannot make $SERVER_BIN executable (permission denied)"
fi

# Quick sanity-check: run the binary with --version to catch link errors or wrong arch
if ! "$SERVER_BIN" --version >/dev/null 2>&1; then
    VERSION_ERR=$("$SERVER_BIN" --version 2>&1 || true)
    die "Server binary fails to run: $VERSION_ERR
  Possible causes:
  • Binary compiled for wrong architecture (check: file $SERVER_BIN)
  • Missing shared libraries (check: ldd $SERVER_BIN)
  • Android W^X / SELinux restriction on execute-from-data"
fi
log "Server binary OK: $SERVER_BIN"

# Check model file exists and is a plausible size (>100 MB)
if [ ! -f "$MODEL_FILE" ]; then
    die "Model file not found: $MODEL_FILE"
fi
MODEL_SIZE_MB=$(( $(stat -c%s "$MODEL_FILE" 2>/dev/null || echo 0) / 1024 / 1024 ))
if [ "$MODEL_SIZE_MB" -lt 100 ]; then
    die "Model file looks too small (${MODEL_SIZE_MB} MB) — download may have been incomplete: $MODEL_FILE"
fi
if [ ! -r "$MODEL_FILE" ]; then
    die "Model file is not readable: $MODEL_FILE (check file permissions)"
fi
log "Model file OK: $MODEL_FILE (${MODEL_SIZE_MB} MB)"

step "Creating server startup script"
# Maximum threads used for inference; capped to avoid overwhelming small devices
MAX_INFERENCE_THREADS=8
INFER_THREADS=$(( CPU_THREADS < MAX_INFERENCE_THREADS ? CPU_THREADS : MAX_INFERENCE_THREADS ))
cat > "$HOME_DIR/start_llm.sh" << LLMSH
#!/data/data/com.termux/files/usr/bin/bash
MODEL="$MODEL_FILE"
SERVER="$SERVER_BIN"
LOG="$LOG_FILE"

if [ ! -f "\$MODEL" ]; then
    echo "❌ Model not found: \$MODEL" | tee -a "\$LOG"
    exit 1
fi

if [ ! -f "\$SERVER" ]; then
    echo "❌ Server binary not found: \$SERVER" | tee -a "\$LOG"
    exit 1
fi

echo "🚀 Starting llama-server (Gemma 2B Q4_K_M)..." | tee -a "\$LOG"
echo "📡 Server will be available at http://127.0.0.1:8080" | tee -a "\$LOG"
echo "Press Ctrl+C to stop"

# stderr is intentionally captured alongside stdout so crash messages appear in the log
exec "\$SERVER" \\
    -m "\$MODEL" \\
    --host 127.0.0.1 \\
    --port 8080 \\
    -c 2048 \\
    --threads $INFER_THREADS \\
    -b 256 \\
    --chat-template gemma
LLMSH
chmod +x "$HOME_DIR/start_llm.sh"
log "Startup script created: ~/start_llm.sh"

step "Setting up auto-start on boot (optional)"
mkdir -p "$HOME_DIR/.termux/boot"
cat > "$HOME_DIR/.termux/boot/start_assistant.sh" << BOOT
#!/data/data/com.termux/files/usr/bin/bash
sleep 10
termux-wake-lock
bash $HOME_DIR/start_llm.sh >> $LOG_FILE 2>&1 &
BOOT
chmod +x "$HOME_DIR/.termux/boot/start_assistant.sh"
log "Auto-start configured (requires Termux:Boot app)"

step "Starting llama-server"
echo -e "${YLW}Starting server in background...${NC}"

# Kill any existing server
pkill -f llama-server 2>/dev/null || true
sleep 1

# Truncate log before fresh start so diagnostics are clean
: > "$LOG_FILE"

# Start server; redirect both stdout and stderr to the log file
bash "$HOME_DIR/start_llm.sh" >> "$LOG_FILE" 2>&1 &
SERVER_PID=$!
echo "$SERVER_PID" > "$HOME_DIR/llama_server.pid"

echo "Waiting for server to start (up to 60 s)..."
SERVER_OK=0
for i in $(seq 1 60); do
    # Abort early if the background process has already exited
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        echo ""
        echo -e "${RED}[✗]${NC} Server process (PID $SERVER_PID) died before becoming ready."
        echo -e "${YLW}[!]${NC} Last lines of $LOG_FILE:"
        tail -20 "$LOG_FILE" 2>/dev/null | sed 's/^/    /'
        echo ""
        echo -e "${YLW}Diagnostics:${NC}"
        echo "  Architecture : $(uname -m)"
        echo "  RAM available: ${AVAIL_RAM_MB} MB / ${TOTAL_RAM_MB} MB total"
        echo "  SELinux      : $SELINUX_STATUS"
        echo "  Binary       : $SERVER_BIN"
        echo "  Model        : $MODEL_FILE (${MODEL_SIZE_MB} MB)"
        echo ""
        echo -e "${YLW}Common fixes:${NC}"
        echo "  • OOM: close other apps; try a smaller model (Q2_K)"
        echo "  • SELinux: su -c setenforce 0  (root required)"
        echo "  • Exec denied: ensure Termux has 'Allow from this source' for installs"
        echo "  • Broken binary: rm -rf $LLM_DIR/build && re-run this script"
        die "Server failed to start."
    fi

    if curl -s http://127.0.0.1:8080/health > /dev/null 2>&1; then
        SERVER_OK=1
        break
    fi
    echo -n "."
    sleep 1
done
echo ""

if [ "$SERVER_OK" -ne 1 ]; then
    echo -e "${RED}[✗]${NC} Server did not become ready within 60 s."
    echo -e "${YLW}[!]${NC} Last lines of $LOG_FILE:"
    tail -20 "$LOG_FILE" 2>/dev/null | sed 's/^/    /'
    die "Server failed to start. Review the log above for details."
fi

log "Server started successfully (PID: $SERVER_PID)"
log "Server log: $LOG_FILE"

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
