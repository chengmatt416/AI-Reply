#!/data/data/com.termux/files/usr/bin/bash
# ════════════════════════════════════════════════════════════════════
#  APK Build Script
#  Compiles the ChatAssistant Android app
# ════════════════════════════════════════════════════════════════════
set -euo pipefail

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[0;33m'
BLU='\033[0;34m'; PRP='\033[0;35m'; CYN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GRN}[✓]${NC} $*"; }
warn() { echo -e "${YLW}[!]${NC} $*"; }
die()  { echo -e "${RED}[✗]${NC} $*"; exit 1; }
step() { echo -e "\n${PRP}━━━ $* ━━━${NC}"; }

HOME_DIR=/data/data/com.termux/files/home
SDK_DIR=$HOME_DIR/android-sdk
PROJ_DIR=$HOME_DIR/ChatAssistant
APK_OUT=$PROJ_DIR/app/build/outputs/apk/release/app-release-unsigned.apk
APK_SIGNED=$HOME_DIR/ChatAssistant.apk

echo -e "${CYN}
╔══════════════════════════════════════╗
║   Building ChatAssistant APK        ║
╚══════════════════════════════════════╝${NC}"

# Check if project exists
[ -d "$PROJ_DIR" ] || die "Project directory not found. Run extract_apk_files.sh first!"

step "Setting up environment"
export ANDROID_HOME=$SDK_DIR
export ANDROID_SDK_ROOT=$SDK_DIR
export PATH="$SDK_DIR/cmdline-tools/latest/bin:$SDK_DIR/platform-tools:$SDK_DIR/build-tools/34.0.0:$PATH"
export JAVA_HOME=$(dirname $(dirname $(readlink -f $(command -v java))))
export GRADLE_OPTS="-Xmx2g -Dorg.gradle.daemon=false -Dorg.gradle.jvmargs=-Xmx2g"
log "Environment configured"

step "Setting up Gradle wrapper"
cd "$PROJ_DIR"
if [ ! -x "$PROJ_DIR/gradlew" ]; then
    gradle wrapper --gradle-version=8.4 --distribution-type=bin --no-daemon 2>/dev/null || true
    chmod +x "$PROJ_DIR/gradlew"
fi
log "Gradle wrapper ready"

step "Building APK (this may take several minutes)"
LOG="$HOME_DIR/build_log.log"
./gradlew clean assembleRelease --no-daemon --stacktrace 2>&1 | tee "$LOG" | grep -E "BUILD|SUCC|FAIL|Error|error" | head -40

if [ ! -f "$APK_OUT" ]; then
    warn "Release build failed, trying debug build..."
    ./gradlew assembleDebug --no-daemon --stacktrace 2>&1 | tee "$LOG" | grep -E "BUILD|SUCC|FAIL|Error|error" | head -40
    APK_OUT=$(find "$PROJ_DIR/app/build" -name "*.apk" 2>/dev/null | head -1)
fi

[ -f "$APK_OUT" ] || die "APK build failed. Check log: cat ~/build_log.log"

step "Processing APK"
ZIPALIGN="$SDK_DIR/build-tools/34.0.0/zipalign"
if [ -f "$ZIPALIGN" ]; then
    "$ZIPALIGN" -v 4 "$APK_OUT" "$APK_SIGNED" 2>/dev/null && log "APK aligned" || cp "$APK_OUT" "$APK_SIGNED"
else
    cp "$APK_OUT" "$APK_SIGNED"
fi

APK_SIZE=$(du -h "$APK_SIGNED" | cut -f1)
log "APK built successfully: $APK_SIGNED ($APK_SIZE)"

step "Installing APK (requires root)"
if su -c "pm install -r '$APK_SIGNED'" 2>/dev/null; then
    log "APK installed successfully"
    PKG="com.chatassistant"
    su -c "appops set $PKG SYSTEM_ALERT_WINDOW allow" 2>/dev/null || true
    su -c "appops set $PKG READ_CALENDAR allow" 2>/dev/null || true
    su -c "appops set $PKG WRITE_CALENDAR allow" 2>/dev/null || true
    su -c "pm grant $PKG android.permission.READ_CALENDAR" 2>/dev/null || true
    su -c "pm grant $PKG android.permission.WRITE_CALENDAR" 2>/dev/null || true
    su -c "pm grant $PKG android.permission.READ_CONTACTS" 2>/dev/null || true
    su -c "dumpsys deviceidle whitelist +com.termux" 2>/dev/null || true
    su -c "dumpsys deviceidle whitelist +$PKG" 2>/dev/null || true
    log "Permissions granted"
else
    warn "Automatic installation failed. Please install manually:"
    warn "  pm install -r $APK_SIGNED"
fi

echo -e "
${GRN}╔════════════════════════════════════════════╗
║   ✅ Build Complete!                       ║
╠════════════════════════════════════════════╣
║  APK Location: ~/ChatAssistant.apk        ║
║  Size: $APK_SIZE                              ║
║                                            ║
║  Next Steps:                               ║
║  1. Open the Chat Assistant app            ║
║  2. Run: bash ~/setup_server.sh            ║
║  3. Run: bash ~/test_server.sh             ║
╚════════════════════════════════════════════╝${NC}"
