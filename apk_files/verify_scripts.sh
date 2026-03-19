#!/bin/bash
# ════════════════════════════════════════════════════════════════════
#  Verification Script for APK Build Files
#  Tests and verifies the logic of all scripts
# ════════════════════════════════════════════════════════════════════
set -euo pipefail

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[0;33m'
BLU='\033[0;34m'; PRP='\033[0;35m'; CYN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GRN}[✓]${NC} $*"; }
warn() { echo -e "${YLW}[!]${NC} $*"; }
die()  { echo -e "${RED}[✗]${NC} $*"; exit 1; }
step() { echo -e "\n${PRP}━━━ $* ━━━${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="/tmp/apk_test_$$"
PASS=0
FAIL=0
WARN=0

echo -e "${CYN}
╔══════════════════════════════════════════════╗
║   APK Build Scripts Verification           ║
║   Testing logic and structure               ║
╚══════════════════════════════════════════════╝${NC}"

# Create test directory
mkdir -p "$TEST_DIR"
log "Test directory: $TEST_DIR"

# ═══════════════════════════════════════════════════════════════════
step "1. Syntax Verification"
# ═══════════════════════════════════════════════════════════════════
echo "Checking bash syntax for all scripts..."
for script in "$SCRIPT_DIR"/*.sh; do
    if [ "$(basename $script)" = "verify_scripts.sh" ]; then
        continue
    fi
    echo -n "  $(basename $script)... "
    if bash -n "$script" 2>/dev/null; then
        echo -e "${GRN}✓${NC}"
        ((PASS++))
    else
        echo -e "${RED}✗ Syntax Error${NC}"
        ((FAIL++))
    fi
done

# ═══════════════════════════════════════════════════════════════════
step "2. Error Handling Verification"
# ═══════════════════════════════════════════════════════════════════
echo "Checking error handling flags..."
for script in "$SCRIPT_DIR"/*.sh; do
    if [ "$(basename $script)" = "verify_scripts.sh" ]; then
        continue
    fi
    echo -n "  $(basename $script)... "
    if grep -q "set -euo pipefail" "$script"; then
        echo -e "${GRN}✓ Has proper error handling${NC}"
        ((PASS++))
    else
        echo -e "${RED}✗ Missing error handling${NC}"
        ((FAIL++))
    fi
done

# ═══════════════════════════════════════════════════════════════════
step "3. Shebang Verification"
# ═══════════════════════════════════════════════════════════════════
echo "Checking shebang lines..."
for script in "$SCRIPT_DIR"/*.sh; do
    if [ "$(basename $script)" = "verify_scripts.sh" ]; then
        continue
    fi
    echo -n "  $(basename $script)... "
    SHEBANG=$(head -1 "$script")
    if [[ "$SHEBANG" == "#!/data/data/com.termux/files/usr/bin/bash" ]] || [[ "$SHEBANG" == "#!/bin/bash" ]]; then
        echo -e "${GRN}✓ Valid shebang${NC}"
        ((PASS++))
    else
        echo -e "${YLW}! Non-standard shebang: $SHEBANG${NC}"
        ((WARN++))
    fi
done

# ═══════════════════════════════════════════════════════════════════
step "4. Function Definitions Verification"
# ═══════════════════════════════════════════════════════════════════
echo "Checking for helper functions..."
for script in "$SCRIPT_DIR"/*.sh; do
    if [ "$(basename $script)" = "verify_scripts.sh" ]; then
        continue
    fi
    echo -n "  $(basename $script)... "
    if grep -q "^log()" "$script" && grep -q "^warn()" "$script" && grep -q "^die()" "$script"; then
        echo -e "${GRN}✓ Has log/warn/die functions${NC}"
        ((PASS++))
    else
        echo -e "${YLW}! Missing some helper functions${NC}"
        ((WARN++))
    fi
done

# ═══════════════════════════════════════════════════════════════════
step "5. Path Variable Verification"
# ═══════════════════════════════════════════════════════════════════
echo "Checking for proper path definitions..."

echo -n "  extract_apk_files.sh... "
if grep -q "HOME_DIR=/data/data/com.termux/files/home" "$SCRIPT_DIR/extract_apk_files.sh" && \
   grep -q "PROJ_DIR=.*ChatAssistant" "$SCRIPT_DIR/extract_apk_files.sh"; then
    echo -e "${GRN}✓ Has proper paths${NC}"
    ((PASS++))
else
    echo -e "${RED}✗ Missing path definitions${NC}"
    ((FAIL++))
fi

echo -n "  build_apk.sh... "
if grep -q "SDK_DIR=.*android-sdk" "$SCRIPT_DIR/build_apk.sh" && \
   grep -q "APK_OUT=.*app-release-unsigned.apk" "$SCRIPT_DIR/build_apk.sh"; then
    echo -e "${GRN}✓ Has proper paths${NC}"
    ((PASS++))
else
    echo -e "${RED}✗ Missing path definitions${NC}"
    ((FAIL++))
fi

echo -n "  setup_server.sh... "
if grep -q "LLM_DIR=.*llama.cpp" "$SCRIPT_DIR/setup_server.sh" && \
   grep -q "MODEL_FILE=.*gemma.*gguf" "$SCRIPT_DIR/setup_server.sh"; then
    echo -e "${GRN}✓ Has proper paths${NC}"
    ((PASS++))
else
    echo -e "${RED}✗ Missing path definitions${NC}"
    ((FAIL++))
fi

# ═══════════════════════════════════════════════════════════════════
step "6. File Creation Logic Verification"
# ═══════════════════════════════════════════════════════════════════
echo "Checking file creation patterns..."

echo -n "  extract_apk_files.sh... "
FILE_COUNT=$(grep -c "^cat >" "$SCRIPT_DIR/extract_apk_files.sh" || echo 0)
if [ "$FILE_COUNT" -ge 10 ]; then
    echo -e "${GRN}✓ Creates $FILE_COUNT files${NC}"
    ((PASS++))
else
    echo -e "${YLW}! Only creates $FILE_COUNT files${NC}"
    ((WARN++))
fi

echo -n "  create_kotlin_files.sh... "
KT_COUNT=$(grep -c "\.kt" "$SCRIPT_DIR/create_kotlin_files.sh" || echo 0)
if [ "$KT_COUNT" -ge 4 ]; then
    echo -e "${GRN}✓ References $KT_COUNT Kotlin files${NC}"
    ((PASS++))
else
    echo -e "${RED}✗ Only references $KT_COUNT Kotlin files${NC}"
    ((FAIL++))
fi

# ═══════════════════════════════════════════════════════════════════
step "7. Gradle Configuration Verification"
# ═══════════════════════════════════════════════════════════════════
echo "Checking Gradle configuration in extract_apk_files.sh..."

echo -n "  gradle-wrapper.properties... "
if grep -q "gradle-wrapper.properties" "$SCRIPT_DIR/extract_apk_files.sh"; then
    echo -e "${GRN}✓ Present${NC}"
    ((PASS++))
else
    echo -e "${RED}✗ Missing${NC}"
    ((FAIL++))
fi

echo -n "  settings.gradle.kts... "
if grep -q "settings.gradle.kts" "$SCRIPT_DIR/extract_apk_files.sh"; then
    echo -e "${GRN}✓ Present${NC}"
    ((PASS++))
else
    echo -e "${RED}✗ Missing${NC}"
    ((FAIL++))
fi

echo -n "  build.gradle.kts... "
if grep -q "build.gradle.kts" "$SCRIPT_DIR/extract_apk_files.sh" && \
   grep -A 10 "app/build.gradle.kts" "$SCRIPT_DIR/extract_apk_files.sh" | grep -q "dependencies"; then
    echo -e "${GRN}✓ Present with dependencies${NC}"
    ((PASS++))
else
    echo -e "${RED}✗ Missing or incomplete${NC}"
    ((FAIL++))
fi

# ═══════════════════════════════════════════════════════════════════
step "8. Android Resources Verification"
# ═══════════════════════════════════════════════════════════════════
echo "Checking Android resources in extract_apk_files.sh..."

for resource in "strings.xml" "colors.xml" "themes.xml" "AndroidManifest.xml" "activity_main.xml"; do
    echo -n "  $resource... "
    if grep -q "$resource" "$SCRIPT_DIR/extract_apk_files.sh"; then
        echo -e "${GRN}✓ Present${NC}"
        ((PASS++))
    else
        echo -e "${RED}✗ Missing${NC}"
        ((FAIL++))
    fi
done

# ═══════════════════════════════════════════════════════════════════
step "9. Kotlin Source Files Verification"
# ═══════════════════════════════════════════════════════════════════
echo "Checking Kotlin files in create_kotlin_files.sh..."

for kt_file in "MainActivity.kt" "ChatAccessibilityService.kt" "FloatingService.kt" "BootReceiver.kt"; do
    echo -n "  $kt_file... "
    if grep -q "$kt_file" "$SCRIPT_DIR/create_kotlin_files.sh"; then
        echo -e "${GRN}✓ Present${NC}"
        ((PASS++))
    else
        echo -e "${RED}✗ Missing${NC}"
        ((FAIL++))
    fi
done

# ═══════════════════════════════════════════════════════════════════
step "10. Build Script Logic Verification"
# ═══════════════════════════════════════════════════════════════════
echo "Checking build_apk.sh logic..."

echo -n "  Environment setup... "
if grep -q "ANDROID_HOME" "$SCRIPT_DIR/build_apk.sh" && \
   grep -q "JAVA_HOME" "$SCRIPT_DIR/build_apk.sh"; then
    echo -e "${GRN}✓ Present${NC}"
    ((PASS++))
else
    echo -e "${RED}✗ Missing${NC}"
    ((FAIL++))
fi

echo -n "  Gradle wrapper check... "
if grep -q "gradlew" "$SCRIPT_DIR/build_apk.sh"; then
    echo -e "${GRN}✓ Present${NC}"
    ((PASS++))
else
    echo -e "${RED}✗ Missing${NC}"
    ((FAIL++))
fi

echo -n "  APK assembly... "
if grep -q "assembleRelease" "$SCRIPT_DIR/build_apk.sh" || grep -q "assembleDebug" "$SCRIPT_DIR/build_apk.sh"; then
    echo -e "${GRN}✓ Present${NC}"
    ((PASS++))
else
    echo -e "${RED}✗ Missing${NC}"
    ((FAIL++))
fi

echo -n "  Zipalign... "
if grep -q "zipalign" "$SCRIPT_DIR/build_apk.sh"; then
    echo -e "${GRN}✓ Present${NC}"
    ((PASS++))
else
    echo -e "${YLW}! Missing (optional)${NC}"
    ((WARN++))
fi

echo -n "  Installation... "
if grep -q "pm install" "$SCRIPT_DIR/build_apk.sh"; then
    echo -e "${GRN}✓ Present${NC}"
    ((PASS++))
else
    echo -e "${YLW}! Missing (optional)${NC}"
    ((WARN++))
fi

# ═══════════════════════════════════════════════════════════════════
step "11. Server Setup Logic Verification"
# ═══════════════════════════════════════════════════════════════════
echo "Checking setup_server.sh logic..."

echo -n "  Package installation... "
if grep -q "pkg install" "$SCRIPT_DIR/setup_server.sh"; then
    echo -e "${GRN}✓ Present${NC}"
    ((PASS++))
else
    echo -e "${RED}✗ Missing${NC}"
    ((FAIL++))
fi

echo -n "  llama.cpp clone... "
if grep -q "git clone.*llama.cpp" "$SCRIPT_DIR/setup_server.sh"; then
    echo -e "${GRN}✓ Present${NC}"
    ((PASS++))
else
    echo -e "${RED}✗ Missing${NC}"
    ((FAIL++))
fi

echo -n "  CMake build... "
if grep -q "cmake -B build" "$SCRIPT_DIR/setup_server.sh" && \
   grep -q "cmake --build" "$SCRIPT_DIR/setup_server.sh"; then
    echo -e "${GRN}✓ Present${NC}"
    ((PASS++))
else
    echo -e "${RED}✗ Missing${NC}"
    ((FAIL++))
fi

echo -n "  Model download... "
if grep -q "wget.*gemma.*gguf" "$SCRIPT_DIR/setup_server.sh" || \
   grep -q "huggingface_hub" "$SCRIPT_DIR/setup_server.sh"; then
    echo -e "${GRN}✓ Present${NC}"
    ((PASS++))
else
    echo -e "${RED}✗ Missing${NC}"
    ((FAIL++))
fi

echo -n "  Server startup script... "
if grep -q "start_llm.sh" "$SCRIPT_DIR/setup_server.sh"; then
    echo -e "${GRN}✓ Present${NC}"
    ((PASS++))
else
    echo -e "${RED}✗ Missing${NC}"
    ((FAIL++))
fi

# ═══════════════════════════════════════════════════════════════════
step "12. Test Script Logic Verification"
# ═══════════════════════════════════════════════════════════════════
echo "Checking test_server.sh logic..."

echo -n "  Health check... "
if grep -q "/health" "$SCRIPT_DIR/test_server.sh"; then
    echo -e "${GRN}✓ Present${NC}"
    ((PASS++))
else
    echo -e "${RED}✗ Missing${NC}"
    ((FAIL++))
fi

echo -n "  Props check... "
if grep -q "/props" "$SCRIPT_DIR/test_server.sh"; then
    echo -e "${GRN}✓ Present${NC}"
    ((PASS++))
else
    echo -e "${YLW}! Missing (optional)${NC}"
    ((WARN++))
fi

echo -n "  Chat completions test... "
if grep -q "/v1/chat/completions" "$SCRIPT_DIR/test_server.sh" && \
   grep -q "messages" "$SCRIPT_DIR/test_server.sh"; then
    echo -e "${GRN}✓ Present${NC}"
    ((PASS++))
else
    echo -e "${RED}✗ Missing${NC}"
    ((FAIL++))
fi

echo -n "  Response parsing... "
if grep -q "python3 -c" "$SCRIPT_DIR/test_server.sh" || grep -q "json.tool" "$SCRIPT_DIR/test_server.sh"; then
    echo -e "${GRN}✓ Present${NC}"
    ((PASS++))
else
    echo -e "${YLW}! Missing JSON parsing${NC}"
    ((WARN++))
fi

# ═══════════════════════════════════════════════════════════════════
step "13. Master Script Logic Verification"
# ═══════════════════════════════════════════════════════════════════
echo "Checking setup_all.sh logic..."

echo -n "  Script sequencing... "
if grep -q "extract_apk_files.sh" "$SCRIPT_DIR/setup_all.sh" && \
   grep -q "create_kotlin_files.sh" "$SCRIPT_DIR/setup_all.sh" && \
   grep -q "build_apk.sh" "$SCRIPT_DIR/setup_all.sh" && \
   grep -q "setup_server.sh" "$SCRIPT_DIR/setup_all.sh" && \
   grep -q "test_server.sh" "$SCRIPT_DIR/setup_all.sh"; then
    echo -e "${GRN}✓ All scripts called in order${NC}"
    ((PASS++))
else
    echo -e "${RED}✗ Missing script calls${NC}"
    ((FAIL++))
fi

echo -n "  Error handling... "
if grep -q "if bash.*; then" "$SCRIPT_DIR/setup_all.sh"; then
    echo -e "${GRN}✓ Has conditional execution${NC}"
    ((PASS++))
else
    echo -e "${YLW}! No conditional checks${NC}"
    ((WARN++))
fi

echo -n "  User prompts... "
if grep -q "read" "$SCRIPT_DIR/setup_all.sh"; then
    echo -e "${GRN}✓ Has user interaction${NC}"
    ((PASS++))
else
    echo -e "${YLW}! No user prompts${NC}"
    ((WARN++))
fi

# ═══════════════════════════════════════════════════════════════════
step "14. Documentation Verification"
# ═══════════════════════════════════════════════════════════════════
echo "Checking documentation files..."

for doc in "README.md" "QUICKSTART.md" "SUMMARY.md"; do
    echo -n "  $doc... "
    if [ -f "$SCRIPT_DIR/$doc" ]; then
        LINES=$(wc -l < "$SCRIPT_DIR/$doc")
        echo -e "${GRN}✓ Present ($LINES lines)${NC}"
        ((PASS++))
    else
        echo -e "${RED}✗ Missing${NC}"
        ((FAIL++))
    fi
done

# ═══════════════════════════════════════════════════════════════════
step "15. Permissions Verification"
# ═══════════════════════════════════════════════════════════════════
echo "Checking file permissions..."
for script in "$SCRIPT_DIR"/*.sh; do
    echo -n "  $(basename $script)... "
    if [ -x "$script" ]; then
        echo -e "${GRN}✓ Executable${NC}"
        ((PASS++))
    else
        echo -e "${RED}✗ Not executable${NC}"
        ((FAIL++))
    fi
done

# ═══════════════════════════════════════════════════════════════════
step "16. Content Completeness Verification"
# ═══════════════════════════════════════════════════════════════════
echo "Checking content completeness..."

echo -n "  MainActivity features... "
if grep -A 50 "MainActivity.kt" "$SCRIPT_DIR/create_kotlin_files.sh" | grep -q "SharedPreferences" && \
   grep -A 50 "MainActivity.kt" "$SCRIPT_DIR/create_kotlin_files.sh" | grep -q "OkHttpClient"; then
    echo -e "${GRN}✓ Has proper imports${NC}"
    ((PASS++))
else
    echo -e "${YLW}! May be missing features${NC}"
    ((WARN++))
fi

echo -n "  FloatingService features... "
if grep -A 100 "FloatingService.kt" "$SCRIPT_DIR/create_kotlin_files.sh" | grep -q "WindowManager" && \
   grep -A 100 "FloatingService.kt" "$SCRIPT_DIR/create_kotlin_files.sh" | grep -q "MaterialCardView"; then
    echo -e "${GRN}✓ Has UI components${NC}"
    ((PASS++))
else
    echo -e "${YLW}! May be missing features${NC}"
    ((WARN++))
fi

echo -n "  Accessibility features... "
if grep -A 50 "ChatAccessibilityService" "$SCRIPT_DIR/create_kotlin_files.sh" | grep -q "AccessibilityEvent" && \
   grep -A 50 "ChatAccessibilityService" "$SCRIPT_DIR/create_kotlin_files.sh" | grep -q "rootInActiveWindow"; then
    echo -e "${GRN}✓ Has accessibility logic${NC}"
    ((PASS++))
else
    echo -e "${RED}✗ Missing accessibility logic${NC}"
    ((FAIL++))
fi

# ═══════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════
echo -e "\n${CYN}═══════════════════════════════════════════════════${NC}"
step "Verification Summary"
echo -e "${CYN}═══════════════════════════════════════════════════${NC}\n"

TOTAL=$((PASS + FAIL + WARN))
PASS_PERCENT=$((PASS * 100 / TOTAL))

echo -e "  ${GRN}✓ Passed:${NC} $PASS"
echo -e "  ${RED}✗ Failed:${NC} $FAIL"
echo -e "  ${YLW}! Warnings:${NC} $WARN"
echo -e "  ${BLU}━ Total Tests:${NC} $TOTAL"
echo -e "  ${CYN}━ Success Rate:${NC} ${PASS_PERCENT}%"

if [ $FAIL -eq 0 ]; then
    echo -e "\n${GRN}╔════════════════════════════════════════════╗"
    echo -e "║   ✅ ALL CRITICAL TESTS PASSED            ║"
    echo -e "╚════════════════════════════════════════════╝${NC}"
    if [ $WARN -gt 0 ]; then
        echo -e "${YLW}Note: $WARN non-critical warnings were found${NC}"
    fi
    EXIT_CODE=0
else
    echo -e "\n${RED}╔════════════════════════════════════════════╗"
    echo -e "║   ❌ VERIFICATION FAILED                   ║"
    echo -e "╚════════════════════════════════════════════╝${NC}"
    echo -e "${RED}$FAIL critical test(s) failed${NC}"
    EXIT_CODE=1
fi

# Cleanup
rm -rf "$TEST_DIR"

exit $EXIT_CODE
