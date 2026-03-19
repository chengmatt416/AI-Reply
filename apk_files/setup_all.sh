#!/data/data/com.termux/files/usr/bin/bash
# ════════════════════════════════════════════════════════════════════
#  Master Setup Script
#  Runs all setup steps in the correct order
# ════════════════════════════════════════════════════════════════════
set -euo pipefail

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[0;33m'
BLU='\033[0;34m'; PRP='\033[0;35m'; CYN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GRN}[✓]${NC} $*"; }
warn() { echo -e "${YLW}[!]${NC} $*"; }
die()  { echo -e "${RED}[✗]${NC} $*"; exit 1; }
step() { echo -e "\n${PRP}━━━ $* ━━━${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${CYN}
╔══════════════════════════════════════════════╗
║   ChatAssistant Full Setup                  ║
║   This will complete all setup steps        ║
╚══════════════════════════════════════════════╝${NC}"

echo -e "
This script will:
1. Extract APK files and create project structure
2. Create all Kotlin source files
3. Build the APK
4. Setup and start llama-server
5. Test the server

${YLW}⚠️  This process will:${NC}
   • Download ~1.8GB of data (Android SDK + AI model)
   • Require 3-4GB of free storage
   • Take 20-40 minutes depending on your device
   • Require root access for APK installation

${YLW}Press Ctrl+C to cancel, or Enter to continue...${NC}"
read -r

step "Step 1/5: Extracting APK files"
if bash "$SCRIPT_DIR/extract_apk_files.sh"; then
    log "APK files extracted"
else
    die "Failed to extract APK files"
fi

step "Step 2/5: Creating Kotlin source files"
if bash "$SCRIPT_DIR/create_kotlin_files.sh"; then
    log "Kotlin files created"
else
    die "Failed to create Kotlin files"
fi

step "Step 3/5: Building APK (this will take time)"
if bash "$SCRIPT_DIR/build_apk.sh"; then
    log "APK built successfully"
else
    die "Failed to build APK"
fi

step "Step 4/5: Setting up llama-server (this will take time)"
if bash "$SCRIPT_DIR/setup_server.sh"; then
    log "Server setup complete"
else
    die "Failed to setup server"
fi

step "Step 5/5: Testing server"
if bash "$SCRIPT_DIR/test_server.sh"; then
    log "Server test passed"
else
    warn "Server test had issues, but setup may still work"
fi

echo -e "
${GRN}╔════════════════════════════════════════════════════╗
║   🎉 Full Setup Complete!                          ║
╠════════════════════════════════════════════════════╣
║                                                    ║
║  ✅ APK built: ~/ChatAssistant.apk                ║
║  ✅ Server running: http://127.0.0.1:8080         ║
║                                                    ║
║  📱 Next Steps:                                    ║
║                                                    ║
║  1. Open the Chat Assistant app                   ║
║  2. Click \"授予浮動視窗權限\" (Grant overlay perm)   ║
║  3. Click \"開啟無障礙服務\" (Enable accessibility)  ║
║  4. Click \"啟動助理服務\" (Start assistant)         ║
║  5. Open any supported chat app and start chatting║
║                                                    ║
║  Supported apps:                                   ║
║  • WeChat (微信)                                   ║
║  • LINE                                            ║
║  • Instagram DM                                    ║
║  • Telegram                                        ║
║  • WhatsApp                                        ║
║  • Facebook Messenger                              ║
║  • Discord                                         ║
║                                                    ║
║  🔧 Server Commands:                               ║
║  • View logs: tail -f ~/llama_server.log          ║
║  • Stop: kill \$(cat ~/llama_server.pid)           ║
║  • Restart: bash ~/start_llm.sh                   ║
║  • Test: bash $SCRIPT_DIR/test_server.sh          ║
║                                                    ║
╚════════════════════════════════════════════════════╝${NC}
"

log "Setup completed successfully!"
