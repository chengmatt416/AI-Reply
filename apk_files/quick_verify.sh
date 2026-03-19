#!/bin/bash
# Quick verification script - simpler version
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0

echo "=== APK Scripts Quick Verification ==="
echo ""

# Test 1: Syntax
echo "1. Syntax Checks:"
for script in "$SCRIPT_DIR"/*.sh; do
    name=$(basename "$script")
    if bash -n "$script" 2>/dev/null; then
        echo "   ✓ $name"
        ((PASS++))
    else
        echo "   ✗ $name - SYNTAX ERROR"
        ((FAIL++))
    fi
done

# Test 2: Error handling
echo ""
echo "2. Error Handling:"
for script in "$SCRIPT_DIR"/*.sh; do
    name=$(basename "$script")
    if grep -q "set -euo pipefail" "$script" 2>/dev/null; then
        echo "   ✓ $name"
        ((PASS++))
    else
        echo "   ✗ $name - Missing error handling"
        ((FAIL++))
    fi
done

# Test 3: Helper functions
echo ""
echo "3. Helper Functions:"
for script in "$SCRIPT_DIR/build_apk.sh" "$SCRIPT_DIR/setup_server.sh" "$SCRIPT_DIR/test_server.sh"; do
    name=$(basename "$script")
    if grep -q "^log()" "$script" && grep -q "^warn()" "$script" && grep -q "^die()" "$script" 2>/dev/null; then
        echo "   ✓ $name"
        ((PASS++))
    else
        echo "   ! $name - Missing some helpers (acceptable)"
    fi
done

# Test 4: Key content
echo ""
echo "4. Key Content Checks:"

echo -n "   Gradle files... "
if grep -q "gradle-wrapper.properties" "$SCRIPT_DIR/extract_apk_files.sh" && \
   grep -q "build.gradle.kts" "$SCRIPT_DIR/extract_apk_files.sh"; then
    echo "✓"
    ((PASS++))
else
    echo "✗"
    ((FAIL++))
fi

echo -n "   Android Manifest... "
if grep -q "AndroidManifest.xml" "$SCRIPT_DIR/extract_apk_files.sh"; then
    echo "✓"
    ((PASS++))
else
    echo "✗"
    ((FAIL++))
fi

echo -n "   Kotlin files... "
if grep -q "MainActivity.kt" "$SCRIPT_DIR/create_kotlin_files.sh" && \
   grep -q "FloatingService.kt" "$SCRIPT_DIR/create_kotlin_files.sh"; then
    echo "✓"
    ((PASS++))
else
    echo "✗"
    ((FAIL++))
fi

echo -n "   Build commands... "
if grep -q "gradlew.*assemble" "$SCRIPT_DIR/build_apk.sh"; then
    echo "✓"
    ((PASS++))
else
    echo "✗"
    ((FAIL++))
fi

echo -n "   llama.cpp setup... "
if grep -q "git clone.*llama.cpp" "$SCRIPT_DIR/setup_server.sh" && \
   grep -q "cmake" "$SCRIPT_DIR/setup_server.sh"; then
    echo "✓"
    ((PASS++))
else
    echo "✗"
    ((FAIL++))
fi

echo -n "   Server tests... "
if grep -q "/health" "$SCRIPT_DIR/test_server.sh" && \
   grep -q "/v1/chat/completions" "$SCRIPT_DIR/test_server.sh"; then
    echo "✓"
    ((PASS++))
else
    echo "✗"
    ((FAIL++))
fi

echo -n "   Master script... "
if grep -q "extract_apk_files.sh" "$SCRIPT_DIR/setup_all.sh" && \
   grep -q "build_apk.sh" "$SCRIPT_DIR/setup_all.sh"; then
    echo "✓"
    ((PASS++))
else
    echo "✗"
    ((FAIL++))
fi

# Test 5: Permissions
echo ""
echo "5. File Permissions:"
for script in "$SCRIPT_DIR"/*.sh; do
    name=$(basename "$script")
    if [ -x "$script" ]; then
        echo "   ✓ $name is executable"
        ((PASS++))
    else
        echo "   ✗ $name is NOT executable"
        ((FAIL++))
    fi
done

# Summary
echo ""
echo "================================"
echo "Summary:"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo "  Total:  $((PASS + FAIL))"
echo ""

if [ $FAIL -eq 0 ]; then
    echo "✅ ALL TESTS PASSED"
    exit 0
else
    echo "❌ $FAIL TEST(S) FAILED"
    exit 1
fi
