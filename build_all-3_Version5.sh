#!/data/data/com.termux/files/usr/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║   Chat Assistant — 一鍵建置腳本 (Termux + KernelSU)         ║
# ║   執行後會：                                                  ║
# ║   1. 安裝 JDK 17 + Android SDK cmdline-tools                ║
# ║   2. 安裝 llama.cpp (Vulkan 加速)                            ║
# ║   3. 下載 Gemma 2B Q4_K_M                                    ║
# ║   4. 建置並簽署 ChatAssistant.apk                            ║
# ║   5. 安裝 APK (root adb)                                     ║
# ║   6. 設定開機自動啟動 llama-server                           ║
# ╚══════════════════════════════════════════════════════════════╝
set -euo pipefail

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[0;33m'
BLU='\033[0;34m'; PRP='\033[0;35m'; CYN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GRN}[✓]${NC} $*"; }
warn() { echo -e "${YLW}[!]${NC} $*"; }
die()  { echo -e "${RED}[✗]${NC} $*"; exit 1; }
step() { echo -e "\n${PRP}━━━ $* ━━━${NC}"; }

# ───────────────────────────── 0. 路徑設定 ─────────────────────────────
PREFIX=/data/data/com.termux/files/usr
HOME_DIR=/data/data/com.termux/files/home
SDK_DIR=$HOME_DIR/android-sdk
PROJ_DIR=$HOME_DIR/ChatAssistant
LLM_DIR=$HOME_DIR/llama.cpp
MODEL_DIR=$HOME_DIR/models
APK_OUT=$PROJ_DIR/app/build/outputs/apk/release/app-release-unsigned.apk
APK_SIGNED=$HOME_DIR/ChatAssistant.apk
KEYSTORE=$HOME_DIR/assistant.keystore
SERVER_URL="http://127.0.0.1:8080"

echo -e "${CYN}
╔══════════════════════════════════════╗
║   Chat Assistant 一鍵建置腳本       ║
║   OnePlus Ace 5 / KernelSU 專用     ║
╚══════════════════════════════════════╝${NC}"

# ───────────────────────────── 1. 基礎套件 ─────────────────────────────
step "安裝基礎套件"
pkg update -y -o Dpkg::Options::="--force-confold" 2>/dev/null || true
pkg install -y \
    openjdk-17 wget unzip git cmake clang binutils \
    ninja patchelf python termux-tools aapt which 2>/dev/null || \
pkg install -y \
    openjdk-17 wget unzip git cmake clang binutils ninja python aapt which 2>/dev/null
log "基礎套件完成"

# ───────────────────────────── 2. Android SDK ─────────────────────────
step "安裝 Android SDK cmdline-tools"
mkdir -p "$SDK_DIR/cmdline-tools"

if [ ! -f "$SDK_DIR/cmdline-tools/latest/bin/sdkmanager" ]; then
    TOOLS_ZIP="$HOME_DIR/cmdline-tools.zip"
    if [ ! -f "$TOOLS_ZIP" ]; then
        warn "下載 cmdline-tools (~130MB)..."
        wget -q --show-progress \
            "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip" \
            -O "$TOOLS_ZIP"
    fi
    unzip -q -o "$TOOLS_ZIP" -d "$SDK_DIR/cmdline-tools"
    mv "$SDK_DIR/cmdline-tools/cmdline-tools" "$SDK_DIR/cmdline-tools/latest" 2>/dev/null || true
    rm -f "$TOOLS_ZIP"
fi
log "cmdline-tools 就緒"

export ANDROID_HOME=$SDK_DIR
export ANDROID_SDK_ROOT=$SDK_DIR
export PATH="$SDK_DIR/cmdline-tools/latest/bin:$SDK_DIR/platform-tools:$SDK_DIR/build-tools/34.0.0:$PATH"
export JAVA_HOME=$(dirname $(dirname $(readlink -f $(command -v java))))

warn "接受 Android SDK 授權..."
for i in 1 2 3; do yes 2>/dev/null | sdkmanager --licenses > /dev/null 2>&1 || true; done

mkdir -p "$SDK_DIR/licenses"
echo -e "\n8933bad161af4178b1185d1a37fbf41ea5269c55\nd56f5187479451eabf01fb78af6dfcb131a6481e\n24333f8a63b6825ea9c5514f83c2829b004d1fee" > "$SDK_DIR/licenses/android-sdk-license"
echo -e "\n84831b9409646a918e30573bab4c9c91346d8abd" > "$SDK_DIR/licenses/android-sdk-preview-license"

if [ ! -d "$SDK_DIR/build-tools/34.0.0" ] || [ ! -d "$SDK_DIR/platforms/android-34" ]; then
    warn "下載 Android build-tools 34 + platform-34 (~400MB)..."
    yes 2>/dev/null | sdkmanager \
        "platform-tools" \
        "build-tools;34.0.0" \
        "platforms;android-34" \
        2>&1 | grep -vE "^$|Warning" || true
fi
yes 2>/dev/null | sdkmanager --licenses > /dev/null 2>&1 || true
log "Android SDK 就緒"

# ───────────────────────────── 3. llama.cpp ─────────────────────────────
step "編譯 llama.cpp (Vulkan GPU 加速)"
if [ ! -f "$LLM_DIR/build/bin/llama-server" ]; then
    if [ ! -d "$LLM_DIR/.git" ]; then
        git clone --depth=1 https://github.com/ggerganov/llama.cpp "$LLM_DIR"
    fi
    cd "$LLM_DIR"
    warn "使用 S8 Gen 3 CPU 最佳化模式 (armv9-a + i8mm + dotprod)"
    cmake -B build \
        -DGGML_VULKAN=OFF \
        -DGGML_OPENCL=OFF \
        -DCMAKE_BUILD_TYPE=Release \
        -DLLAMA_BUILD_SERVER=ON \
        -DGGML_NATIVE=OFF \
        -DCMAKE_C_FLAGS="-march=armv9-a+dotprod+i8mm" \
        -DCMAKE_CXX_FLAGS="-march=armv9-a+dotprod+i8mm"
    cmake --build build --config Release -j"$(nproc)"
    log "llama.cpp 編譯完成"
else
    log "llama.cpp 已存在，跳過"
fi

# ───────────────────────────── 4. Gemma 2B 模型 ─────────────────────────
step "下載 Gemma 2B Q4_K_M"
mkdir -p "$MODEL_DIR"
MODEL_FILE="$MODEL_DIR/gemma-2-2b-it-Q4_K_M.gguf"
if [ ! -f "$MODEL_FILE" ]; then
    warn "下載模型 (~1.6GB)，請耐心等候..."
    wget -q --show-progress \
        "https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf" \
        -O "$MODEL_FILE" || {
        warn "直接下載失敗，嘗試備用鏡像..."
        pip3 install -q huggingface_hub 2>/dev/null || true
        python3 -c "
from huggingface_hub import hf_hub_download
hf_hub_download(
    repo_id='bartowski/gemma-2-2b-it-GGUF',
    filename='gemma-2-2b-it-Q4_K_M.gguf',
    local_dir='$MODEL_DIR'
)
print('done')
"
    }
    log "模型下載完成"
else
    log "模型已存在，跳過"
fi

# ───────────────────────────── 5. 建立 Android 專案 ─────────────────────
step "建立 Android 專案原始碼"
rm -rf "$PROJ_DIR"
mkdir -p "$PROJ_DIR"/{app/src/main/{kotlin/com/chatassistant,res/{layout,values,xml,drawable,mipmap-hdpi}},gradle/wrapper}

cat > "$PROJ_DIR/gradle/wrapper/gradle-wrapper.properties" << 'GPROPS'
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.4-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
GPROPS

cat > "$PROJ_DIR/settings.gradle.kts" << 'SETTINGS'
pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "ChatAssistant"
include(":app")
SETTINGS

cat > "$PROJ_DIR/build.gradle.kts" << 'ROOTBUILD'
plugins {
    id("com.android.application") version "8.3.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
}
ROOTBUILD

cat > "$PROJ_DIR/app/build.gradle.kts" << 'APPBUILD'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}
android {
    namespace = "com.chatassistant"
    compileSdk = 34
    defaultConfig {
        applicationId = "com.chatassistant"
        minSdk = 31; targetSdk = 34
        versionCode = 1; versionName = "1.0"
    }
    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("debug")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { viewBinding = true }
}
dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    implementation("androidx.lifecycle:lifecycle-service:2.7.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.json:json:20240303")
}
APPBUILD

cat > "$PROJ_DIR/local.properties" << LOCALPROPS
sdk.dir=$SDK_DIR
LOCALPROPS

cat > "$PROJ_DIR/gradle.properties" << 'GPROPS'
android.useAndroidX=true
android.enableJetifier=true
org.gradle.jvmargs=-Xmx2g -XX:MaxMetaspaceSize=512m
org.gradle.daemon=false
kotlin.code.style=official
GPROPS

AAPT2_BIN="$SDK_DIR/build-tools/34.0.0/aapt2"
if [ -x "$AAPT2_BIN" ]; then
    chmod +x "$AAPT2_BIN"
    echo "android.aapt2FromMavenOverride=$AAPT2_BIN" >> "$PROJ_DIR/gradle.properties"
else
    warn "找不到 $AAPT2_BIN，讓 Gradle 自行下載 aapt2（已移除 override）"
fi

cat > "$PROJ_DIR/app/src/main/AndroidManifest.xml" << 'MANIFEST'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE"/>
    <uses-permission android:name="android.permission.READ_CALENDAR"/>
    <uses-permission android:name="android.permission.WRITE_CALENDAR"/>
    <uses-permission android:name="android.permission.SET_ALARM"/>
    <uses-permission android:name="android.permission.READ_CONTACTS"/>
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:roundIcon="@mipmap/ic_launcher"
        android:supportsRtl="true"
        android:theme="@style/Theme.ChatAssistant">
        <activity android:name=".MainActivity" android:exported="true"
            android:windowSoftInputMode="adjustResize">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <service android:name=".ChatAccessibilityService" android:exported="true"
            android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE">
            <intent-filter>
                <action android:name="android.accessibilityservice.AccessibilityService"/>
            </intent-filter>
            <meta-data android:name="android.accessibilityservice"
                android:resource="@xml/accessibility_config"/>
        </service>
        <service android:name=".FloatingService" android:exported="false"
            android:foregroundServiceType="specialUse">
            <property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="Chat overlay assistant"/>
        </service>
        <receiver android:name=".BootReceiver" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
            </intent-filter>
        </receiver>
    </application>
</manifest>
MANIFEST

cat > "$PROJ_DIR/app/src/main/res/values/strings.xml" << 'STR'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">Chat Assistant</string>
    <string name="accessibility_desc">自動讀取聊天並生成 AI 回覆建議</string>
</resources>
STR

cat > "$PROJ_DIR/app/src/main/res/values/colors.xml" << 'COL'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="purple_200">#FFBB86FC</color>
    <color name="purple_500">#FF6200EE</color>
    <color name="teal_200">#FF03DAC5</color>
    <color name="black">#FF000000</color>
    <color name="white">#FFFFFFFF</color>
</resources>
COL

cat > "$PROJ_DIR/app/src/main/res/values/themes.xml" << 'THEME'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="Theme.ChatAssistant" parent="Theme.Material3.DayNight.NoActionBar">
        <item name="colorPrimary">#A78BFA</item>
        <item name="android:statusBarColor">@android:color/transparent</item>
        <item name="android:navigationBarColor">@android:color/transparent</item>
        <item name="android:windowLightStatusBar">false</item>
    </style>
</resources>
THEME

cat > "$PROJ_DIR/app/src/main/res/xml/accessibility_config.xml" << 'ACC'
<?xml version="1.0" encoding="utf-8"?>
<accessibility-service xmlns:android="http://schemas.android.com/apk/res/android"
    android:accessibilityEventTypes="typeWindowContentChanged|typeWindowStateChanged|typeViewFocused"
    android:accessibilityFeedbackType="feedbackGeneric"
    android:accessibilityFlags="flagReportViewIds|flagRetrieveInteractiveWindows"
    android:canRetrieveWindowContent="true"
    android:canPerformGestures="true"
    android:notificationTimeout="300"
    android:description="@string/accessibility_desc"
    android:packageNames="com.tencent.mm,com.linecorp.line,jp.naver.line.android,org.telegram.messenger,com.whatsapp,com.facebook.orca,com.instagram.android,com.discord"/>
ACC

cat > "$PROJ_DIR/app/src/main/res/drawable/dot_green.xml" << 'D'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="oval">
    <solid android:color="#FF10B981"/>
</shape>
D
cat > "$PROJ_DIR/app/src/main/res/drawable/dot_red.xml" << 'D'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="oval">
    <solid android:color="#FFFF6B6B"/>
</shape>
D
cat > "$PROJ_DIR/app/src/main/res/drawable/bg_glow_purple.xml" << 'D'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="oval">
    <gradient android:type="radial" android:gradientRadius="50%"
        android:startColor="#FFA78BFA" android:endColor="#00A78BFA"
        android:centerX="0.5" android:centerY="0.5"/>
</shape>
D

python3 - << 'PYICON'
import struct, zlib, os
def make_png(w, h, color_rgba):
    def chunk(t, d):
        c = zlib.crc32(t + d) & 0xffffffff
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", c)
    r, g, b, a = color_rgba
    raw = b""
    for _ in range(h):
        row = b"\x00" + bytes([r, g, b, a] * w)
        raw += row
    compressed = zlib.compress(raw, 9)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", compressed)
    png += chunk(b"IEND", b"")
    return png
out = "/data/data/com.termux/files/home/ChatAssistant/app/src/main/res/mipmap-hdpi"
os.makedirs(out, exist_ok=True)
data = make_png(72, 72, (167, 139, 250, 255))
open(f"{out}/ic_launcher.png", "wb").write(data)
open(f"{out}/ic_launcher_round.png", "wb").write(data)
print("icon ok")
PYICON

cat > "$PROJ_DIR/app/src/main/res/layout/activity_main.xml" << 'LAYOUT'
<?xml version="1.0" encoding="utf-8"?>
<androidx.coordinatorlayout.widget.CoordinatorLayout
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="#080B14"
    android:fitsSystemWindows="true">
    <View android:layout_width="300dp" android:layout_height="300dp"
        android:layout_gravity="top|center_horizontal" android:layout_marginTop="-80dp"
        android:alpha="0.25" android:background="@drawable/bg_glow_purple"/>
    <LinearLayout android:layout_width="match_parent" android:layout_height="match_parent"
        android:orientation="vertical" android:paddingTop="24dp">
        <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
            android:orientation="vertical" android:paddingHorizontal="24dp" android:paddingBottom="28dp">
            <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:text="Chat" android:textColor="#FFA78BFA" android:textSize="34sp"
                android:fontFamily="sans-serif-medium"/>
            <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:text="Assistant" android:textColor="#FFFFFFFF" android:textSize="34sp"
                android:fontFamily="sans-serif-medium" android:layout_marginTop="-8dp"/>
            <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:text="由 Gemma 2B 驅動的本地 AI 回覆助理" android:textColor="#80FFFFFF"
                android:textSize="13sp" android:layout_marginTop="6dp"/>
        </LinearLayout>
        <androidx.core.widget.NestedScrollView android:layout_width="match_parent"
            android:layout_height="0dp" android:layout_weight="1"
            android:paddingHorizontal="16dp" android:clipToPadding="false">
            <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
                android:orientation="vertical" android:paddingBottom="32dp">
                <com.google.android.material.card.MaterialCardView
                    android:id="@+id/cardStatus" android:layout_width="match_parent"
                    android:layout_height="wrap_content" android:layout_marginBottom="12dp"
                    app:cardBackgroundColor="#0DFFFFFF" app:cardCornerRadius="20dp"
                    app:strokeColor="#1AFFFFFF" app:strokeWidth="1dp" app:cardElevation="0dp">
                    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
                        android:orientation="vertical" android:padding="20dp">
                        <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
                            android:orientation="horizontal" android:gravity="center_vertical">
                            <TextView android:layout_width="0dp" android:layout_height="wrap_content"
                                android:layout_weight="1" android:text="系統狀態"
                                android:textColor="#FFFFFFFF" android:textSize="15sp"
                                android:fontFamily="sans-serif-medium"/>
                            <View android:id="@+id/dotLlm" android:layout_width="8dp"
                                android:layout_height="8dp" android:background="@drawable/dot_red"/>
                        </LinearLayout>
                        <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
                            android:orientation="horizontal" android:gravity="center_vertical"
                            android:layout_marginTop="16dp">
                            <TextView android:layout_width="0dp" android:layout_height="wrap_content"
                                android:layout_weight="1" android:text="🤖  LLM 伺服器"
                                android:textColor="#B3FFFFFF" android:textSize="13sp"/>
                            <TextView android:id="@+id/tvLlmStatus" android:layout_width="wrap_content"
                                android:layout_height="wrap_content" android:text="未連線"
                                android:textColor="#FF6B6B" android:textSize="12sp"/>
                        </LinearLayout>
                        <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
                            android:orientation="horizontal" android:gravity="center_vertical"
                            android:layout_marginTop="10dp">
                            <TextView android:layout_width="0dp" android:layout_height="wrap_content"
                                android:layout_weight="1" android:text="♿  無障礙服務"
                                android:textColor="#B3FFFFFF" android:textSize="13sp"/>
                            <TextView android:id="@+id/tvAccessStatus" android:layout_width="wrap_content"
                                android:layout_height="wrap_content" android:text="未開啟"
                                android:textColor="#FF6B6B" android:textSize="12sp"/>
                        </LinearLayout>
                        <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
                            android:orientation="horizontal" android:gravity="center_vertical"
                            android:layout_marginTop="10dp">
                            <TextView android:layout_width="0dp" android:layout_height="wrap_content"
                                android:layout_weight="1" android:text="🪟  浮動視窗權限"
                                android:textColor="#B3FFFFFF" android:textSize="13sp"/>
                            <TextView android:id="@+id/tvOverlayStatus" android:layout_width="wrap_content"
                                android:layout_height="wrap_content" android:text="未授權"
                                android:textColor="#FF6B6B" android:textSize="12sp"/>
                        </LinearLayout>
                        <com.google.android.material.button.MaterialButton
                            android:id="@+id/btnCheckStatus" android:layout_width="match_parent"
                            android:layout_height="44dp" android:layout_marginTop="16dp"
                            android:text="重新檢查狀態" android:textSize="13sp"
                            app:cornerRadius="12dp" app:backgroundTint="#26A78BFA"
                            app:strokeColor="#4DA78BFA" app:strokeWidth="1dp"/>
                    </LinearLayout>
                </com.google.android.material.card.MaterialCardView>
                <com.google.android.material.card.MaterialCardView
                    android:layout_width="match_parent" android:layout_height="wrap_content"
                    android:layout_marginBottom="12dp" app:cardBackgroundColor="#0DFFFFFF"
                    app:cardCornerRadius="20dp" app:strokeColor="#1AFFFFFF"
                    app:strokeWidth="1dp" app:cardElevation="0dp">
                    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
                        android:orientation="vertical" android:padding="20dp">
                        <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
                            android:text="快速設定" android:textColor="#FFFFFFFF"
                            android:textSize="15sp" android:fontFamily="sans-serif-medium"
                            android:layout_marginBottom="16dp"/>
                        <com.google.android.material.button.MaterialButton
                            android:id="@+id/btnOverlayPerm"
                            style="@style/Widget.Material3.Button.OutlinedButton"
                            android:layout_width="match_parent" android:layout_height="48dp"
                            android:layout_marginBottom="10dp" android:text="① 授予浮動視窗權限"
                            android:textColor="#A78BFA" app:cornerRadius="14dp"
                            app:strokeColor="#4DA78BFA"/>
                        <com.google.android.material.button.MaterialButton
                            android:id="@+id/btnAccessibility"
                            style="@style/Widget.Material3.Button.OutlinedButton"
                            android:layout_width="match_parent" android:layout_height="48dp"
                            android:layout_marginBottom="10dp" android:text="② 開啟無障礙服務"
                            android:textColor="#A78BFA" app:cornerRadius="14dp"
                            app:strokeColor="#4DA78BFA"/>
                        <com.google.android.material.button.MaterialButton
                            android:id="@+id/btnStartService" android:layout_width="match_parent"
                            android:layout_height="52dp" android:text="③ 啟動助理服務"
                            android:textSize="14sp" android:fontFamily="sans-serif-medium"
                            app:cornerRadius="14dp" app:backgroundTint="#A78BFA"/>
                    </LinearLayout>
                </com.google.android.material.card.MaterialCardView>
                <com.google.android.material.card.MaterialCardView
                    android:layout_width="match_parent" android:layout_height="wrap_content"
                    app:cardBackgroundColor="#0DFFFFFF" app:cardCornerRadius="20dp"
                    app:strokeColor="#1AFFFFFF" app:strokeWidth="1dp" app:cardElevation="0dp">
                    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
                        android:orientation="vertical" android:padding="20dp">
                        <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
                            android:text="進階設定" android:textColor="#FFFFFFFF"
                            android:textSize="15sp" android:fontFamily="sans-serif-medium"
                            android:layout_marginBottom="16dp"/>
                        <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
                            android:text="LLM 伺服器位址" android:textColor="#80FFFFFF"
                            android:textSize="11sp" android:layout_marginBottom="4dp"/>
                        <com.google.android.material.textfield.TextInputLayout
                            android:layout_width="match_parent" android:layout_height="wrap_content"
                            android:layout_marginBottom="16dp"
                            style="@style/Widget.Material3.TextInputLayout.OutlinedBox.Dense"
                            app:boxCornerRadiusBottomEnd="12dp" app:boxCornerRadiusBottomStart="12dp"
                            app:boxCornerRadiusTopEnd="12dp" app:boxCornerRadiusTopStart="12dp"
                            app:boxStrokeColor="#33A78BFA" app:hintTextColor="#80FFFFFF">
                            <com.google.android.material.textfield.TextInputEditText
                                android:id="@+id/etServerUrl" android:layout_width="match_parent"
                                android:layout_height="wrap_content"
                                android:text="http://127.0.0.1:8080"
                                android:textColor="#FFFFFFFF" android:textSize="13sp"
                                android:fontFamily="monospace" android:inputType="textUri"/>
                        </com.google.android.material.textfield.TextInputLayout>
                        <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
                            android:orientation="horizontal" android:gravity="center_vertical"
                            android:layout_marginBottom="6dp">
                            <TextView android:layout_width="0dp" android:layout_height="wrap_content"
                                android:layout_weight="1" android:text="最大 Token 數"
                                android:textColor="#80FFFFFF" android:textSize="11sp"/>
                            <TextView android:id="@+id/tvTokenCount" android:layout_width="wrap_content"
                                android:layout_height="wrap_content" android:text="256"
                                android:textColor="#A78BFA" android:textSize="12sp"/>
                        </LinearLayout>
                        <com.google.android.material.slider.Slider
                            android:id="@+id/sliderTokens" android:layout_width="match_parent"
                            android:layout_height="wrap_content" android:valueFrom="128"
                            android:valueTo="512" android:value="256" android:stepSize="64"
                            app:thumbColor="#A78BFA" app:trackColorActive="#A78BFA"
                            app:trackColorInactive="#33A78BFA" android:layout_marginBottom="16dp"/>
                        <com.google.android.material.button.MaterialButton
                            android:id="@+id/btnSaveSettings" android:layout_width="match_parent"
                            android:layout_height="44dp" android:text="儲存設定"
                            app:cornerRadius="12dp" app:backgroundTint="#26A78BFA"
                            app:strokeColor="#4DA78BFA" app:strokeWidth="1dp"/>
                    </LinearLayout>
                </com.google.android.material.card.MaterialCardView>
            </LinearLayout>
        </androidx.core.widget.NestedScrollView>
    </LinearLayout>
</androidx.coordinatorlayout.widget.CoordinatorLayout>
LAYOUT

log "資源檔建立完成"

step "寫入 Kotlin 原始碼"

cat > "$PROJ_DIR/app/src/main/kotlin/com/chatassistant/MainActivity.kt" << 'KT'
package com.chatassistant
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.*
import android.net.Uri; import android.os.Bundle
import android.provider.Settings; import android.widget.Toast
import android.view.accessibility.AccessibilityManager
import androidx.appcompat.app.AppCompatActivity
import com.chatassistant.databinding.ActivityMainBinding
import kotlinx.coroutines.*
import okhttp3.OkHttpClient; import okhttp3.Request
import java.util.concurrent.TimeUnit

class MainActivity : AppCompatActivity() {
    private lateinit var b: ActivityMainBinding
    private val prefs by lazy { getSharedPreferences("assistant_prefs", MODE_PRIVATE) }
    private val http = OkHttpClient.Builder().connectTimeout(2, TimeUnit.SECONDS).build()

    override fun onCreate(s: Bundle?) {
        super.onCreate(s)
        window.statusBarColor = 0x00000000.toInt()
        window.navigationBarColor = 0x00000000.toInt()
        b = ActivityMainBinding.inflate(layoutInflater); setContentView(b.root)
        loadSettings(); setupListeners(); checkStatuses()
    }
    override fun onResume() { super.onResume(); checkStatuses() }

    private fun loadSettings() {
        b.etServerUrl.setText(prefs.getString("server_url","http://127.0.0.1:8080"))
        val t = prefs.getInt("max_tokens",256).toFloat().coerceIn(128f,512f)
        b.sliderTokens.value = t; b.tvTokenCount.text = t.toInt().toString()
    }
    private fun setupListeners() {
        b.btnOverlayPerm.setOnClickListener {
            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName")))
        }
        b.btnAccessibility.setOnClickListener {
            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
        }
        b.btnStartService.setOnClickListener {
            if (!Settings.canDrawOverlays(this)) {
                Toast.makeText(this,"請先授予浮動視窗權限",Toast.LENGTH_SHORT).show(); return@setOnClickListener
            }
            if (!isAccessibilityEnabled()) {
                Toast.makeText(this,"請先開啟無障礙服務",Toast.LENGTH_SHORT).show(); return@setOnClickListener
            }
            startForegroundService(Intent(this,FloatingService::class.java).apply{action="START"})
            Toast.makeText(this,"✅ 助理服務已啟動",Toast.LENGTH_SHORT).show()
            b.btnStartService.text = "③ 服務運行中 ✓"
        }
        b.btnCheckStatus.setOnClickListener { checkStatuses(); checkLlm() }
        b.sliderTokens.addOnChangeListener { _,v,_ -> b.tvTokenCount.text = v.toInt().toString() }
        b.btnSaveSettings.setOnClickListener {
            prefs.edit()
                .putString("server_url", b.etServerUrl.text.toString())
                .putInt("max_tokens", b.sliderTokens.value.toInt()).apply()
            Toast.makeText(this,"設定已儲存",Toast.LENGTH_SHORT).show()
        }
    }
    private fun checkStatuses() {
        val ov = Settings.canDrawOverlays(this)
        b.tvOverlayStatus.text = if(ov) "✓ 已授權" else "未授權"
        b.tvOverlayStatus.setTextColor(if(ov) 0xFF03DAC5.toInt() else 0xFFFF6B6B.toInt())
        val ac = isAccessibilityEnabled()
        b.tvAccessStatus.text = if(ac) "✓ 已開啟" else "未開啟"
        b.tvAccessStatus.setTextColor(if(ac) 0xFF03DAC5.toInt() else 0xFFFF6B6B.toInt())
    }
    private fun checkLlm() {
        val url = prefs.getString("server_url","http://127.0.0.1:8080")!!
        CoroutineScope(Dispatchers.IO).launch {
            val ok = runCatching {
                http.newCall(Request.Builder().url("$url/health").build()).execute().isSuccessful
            }.getOrDefault(false)
            withContext(Dispatchers.Main) {
                b.tvLlmStatus.text = if(ok) "✓ 已連線" else "無法連線"
                b.tvLlmStatus.setTextColor(if(ok) 0xFF03DAC5.toInt() else 0xFFFF6B6B.toInt())
                b.dotLlm.background = getDrawable(if(ok) R.drawable.dot_green else R.drawable.dot_red)
            }
        }
    }
    private fun isAccessibilityEnabled(): Boolean {
        val am = getSystemService(AccessibilityManager::class.java)
        return am.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
            .any { it.resolveInfo.serviceInfo.packageName == packageName }
    }
}
KT

cat > "$PROJ_DIR/app/src/main/kotlin/com/chatassistant/ChatAccessibilityService.kt" << 'KT'
package com.chatassistant
import android.accessibilityservice.AccessibilityService
import android.content.Intent; import android.graphics.Rect
import android.view.accessibility.AccessibilityEvent; import android.view.accessibility.AccessibilityNodeInfo

class ChatAccessibilityService : AccessibilityService() {
    companion object {
        const val ACTION_NEW_CONTENT = "com.chatassistant.NEW_CONTENT"
        const val ACTION_UPDATE_POS  = "com.chatassistant.UPDATE_POS"
    }
    private val supported = setOf(
        "com.instagram.android",
        "com.linecorp.line", "jp.naver.line.android",
        "org.telegram.messenger",
        "com.whatsapp",
        "com.facebook.orca",
        "com.tencent.mm",
        "com.discord"
    )
    private var lastContent = ""; private var lastTop = -1

    override fun onAccessibilityEvent(e: AccessibilityEvent) {
        val pkg = e.packageName?.toString() ?: return
        if (pkg !in supported) return
        val root = rootInActiveWindow ?: return
        try {
            // Instagram: 僅在聊天室畫面才啟用（必須有輸入框且有「訊息/Send message」相關元素）
            if (pkg == "com.instagram.android" && !isInstagramChat(root)) return

            findInput(root)?.let { n ->
                val r = Rect(); n.getBoundsInScreen(r)
                if (r.top != lastTop) { lastTop = r.top; sendPos(r.top, r.bottom, pkg) }
                n.recycle()
            }
            val msgs = buildList { collectText(root, this, 0) }.takeLast(8).joinToString("\n")
            if (msgs.isNotBlank() && msgs != lastContent) { lastContent = msgs; sendContent(msgs, pkg) }
        } finally { root.recycle() }
    }

    private fun isInstagramChat(root: AccessibilityNodeInfo): Boolean {
        // 1) 必須找到可編輯的文字輸入框（聊天輸入欄）
        val input = findInput(root) ?: return false
        // 2) 畫面上需出現傳送訊息的提示文字/描述
        val hasSend = containsText(root, Regex("(Send message|發送訊���|傳送訊息|Message)", RegexOption.IGNORE_CASE))
        input.recycle()
        return hasSend
    }

    private fun containsText(n: AccessibilityNodeInfo, pattern: Regex): Boolean {
        val t = n.text?.toString() ?: n.contentDescription?.toString()
        if (t != null && pattern.containsMatchIn(t)) return true
        for (i in 0 until n.childCount) {
            val c = n.getChild(i) ?: continue
            val hit = containsText(c, pattern)
            c.recycle()
            if (hit) return true
        }
        return false
    }

    private fun findInput(n: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        if (n.isEditable && n.className?.contains("EditText") == true) return n
        for (i in 0 until n.childCount) {
            val c = n.getChild(i) ?: continue
            val f = findInput(c); if (f != null) return f; c.recycle()
        }; return null
    }
    private fun collectText(n: AccessibilityNodeInfo, out: MutableList<String>, depth: Int) {
        if (depth > 15) return
        val t = n.text?.toString()?.trim()
        if (!t.isNullOrBlank() && t.length > 3 &&
            !t.matches(Regex("""\d{1,2}:\d{2}(:\d{2})?""")) &&
            !t.matches(Regex("""\d{1,2}/\d{1,2}"""))) out.add(t)
        for (i in 0 until n.childCount) {
            val c = n.getChild(i) ?: continue; collectText(c, out, depth+1); c.recycle()
        }
    }
    private fun sendPos(top: Int, bot: Int, pkg: String) =
        startService(Intent(this, FloatingService::class.java).apply {
            action = ACTION_UPDATE_POS; putExtra("input_top",top); putExtra("input_bottom",bot); putExtra("pkg",pkg)
        })
    private fun sendContent(c: String, pkg: String) =
        startService(Intent(this, FloatingService::class.java).apply {
            action = ACTION_NEW_CONTENT; putExtra("content",c); putExtra("pkg",pkg)
        })
    override fun onInterrupt() {}
}
KT

cat > "$PROJ_DIR/app/src/main/kotlin/com/chatassistant/FloatingService.kt" << 'KT'
package com.chatassistant
import android.animation.*; import android.app.*
import android.content.*; import android.content.res.ColorStateList
import android.graphics.*; import android.os.*
import android.provider.AlarmClock; import android.provider.CalendarContract
import android.view.*; import android.view.animation.*
import android.widget.*
import androidx.core.app.NotificationCompat
import com.google.android.material.card.MaterialCardView
import kotlinx.coroutines.*
import okhttp3.*; import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray; import org.json.JSONObject
import java.text.SimpleDateFormat; import java.util.*
import java.util.concurrent.TimeUnit

class FloatingService : Service() {
    private lateinit var wm: WindowManager; private lateinit var root: FrameLayout
    private lateinit var params: WindowManager.LayoutParams
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private lateinit var card: MaterialCardView; private lateinit var statusLabel: TextView
    private lateinit var loadingBar: ProgressBar; private lateinit var contentArea: LinearLayout
    private lateinit var chipRow: LinearLayout; private lateinit var actionRow: LinearLayout
    private val prefs by lazy { getSharedPreferences("assistant_prefs", MODE_PRIVATE) }
    private val http = OkHttpClient.Builder().connectTimeout(3,TimeUnit.SECONDS).readTimeout(20,TimeUnit.SECONDS).build()
    private var inputTop = 0; private var screenH = 0; private var isExpanded = true

    data class Ai(val replies: List<String>, val actions: List<Act>)
    data class Act(val type: String, val title: String="", val date: String="", val time: String="", val label: String="")

    override fun onCreate() {
        super.onCreate(); notif(); screenH = resources.displayMetrics.heightPixels; buildOverlay()
    }
    override fun onStartCommand(i: Intent?, f: Int, s: Int): Int {
        when (i?.action) {
            "START" -> show()
            ChatAccessibilityService.ACTION_UPDATE_POS -> {
                inputTop = i.getIntExtra("input_top", inputTop); updatePos(); show()
            }
            ChatAccessibilityService.ACTION_NEW_CONTENT -> {
                val c = i.getStringExtra("content") ?: return START_STICKY
                show(); if (isExpanded) generate(c, i.getStringExtra("pkg") ?: "")
            }
        }; return START_STICKY
    }
    override fun onBind(i: Intent?) = null
    override fun onDestroy() { scope.cancel(); runCatching { wm.removeView(root) }; super.onDestroy() }

    private fun buildOverlay() {
        wm = getSystemService(WINDOW_SERVICE) as WindowManager; root = FrameLayout(this)
        params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        ).apply { gravity = Gravity.BOTTOM or Gravity.START; y = 200 }
        buildUI(); wm.addView(root, params); root.visibility = View.GONE
    }

    private fun buildUI() {
        val dp = resources.displayMetrics.density; fun Int.dp() = (this * dp).toInt()
        card = MaterialCardView(this).apply {
            radius = 22f * dp; strokeWidth = 1.dp(); strokeColor = 0x33FFFFFF
            setCardBackgroundColor(0xCC0D1117.toInt()); cardElevation = 8f * dp; useCompatPadding = false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            card.setRenderEffect(RenderEffect.createBlurEffect(16f,16f,Shader.TileMode.CLAMP))
        }
        val inner = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; setPadding(14.dp(),10.dp(),14.dp(),12.dp())
        }
        val hdr = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        val dot = View(this).apply {
            background = getDrawable(R.drawable.dot_green)
            layoutParams = LinearLayout.LayoutParams(8.dp(),8.dp()).apply { marginEnd = 8.dp() }
        }
        statusLabel = TextView(this).apply {
            text = "✦ AI 回覆助理"; textSize = 13f; setTextColor(0xE0FFFFFFu.toInt())
            typeface = Typeface.DEFAULT_BOLD
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        }
        val colBtn = ImageView(this).apply {
            setImageResource(android.R.drawable.arrow_down_float)
            setColorFilter(0x80FFFFFF.toInt())
            layoutParams = LinearLayout.LayoutParams(24.dp(),24.dp()).apply { marginStart=6.dp() }
            setOnClickListener { toggleExpand() }
        }
        val closeBtn = ImageView(this).apply {
            setImageResource(android.R.drawable.ic_menu_close_clear_cancel)
            setColorFilter(0x60FFFFFF.toInt())
            layoutParams = LinearLayout.LayoutParams(24.dp(),24.dp()).apply { marginStart=6.dp() }
            setOnClickListener { hide() }
        }
        hdr.addView(dot); hdr.addView(statusLabel); hdr.addView(colBtn); hdr.addView(closeBtn)
        loadingBar = ProgressBar(this,null,android.R.attr.progressBarStyleHorizontal).apply {
            isIndeterminate = true; indeterminateTintList = ColorStateList.valueOf(0xFFA78BFA.toInt())
            visibility = View.GONE; layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,2.dp())
        }
        val div = View(this).apply {
            setBackgroundColor(0x1AFFFFFF); layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,1).apply{topMargin=8.dp();bottomMargin=8.dp()}
        }
        contentArea = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        chipRow = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        actionRow = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        contentArea.addView(chipRow); contentArea.addView(actionRow)
        inner.addView(hdr); inner.addView(loadingBar); inner.addView(div); inner.addView(contentArea)
        card.addView(inner)
        val lp = FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT).apply {
            leftMargin=12.dp(); rightMargin=12.dp(); bottomMargin=4.dp()
        }
        root.addView(card, lp)
    }

    private fun generate(chat: String, pkg: String) {
        loadingBar.visibility = View.VISIBLE; statusLabel.text = "⏳ 生成中..."
        chipRow.removeAllViews(); actionRow.removeAllViews()
        scope.launch {
            val cal = calCtx()
            val result = withContext(Dispatchers.IO) { callLlm(chat, pkg, cal) }
            loadingBar.visibility = View.GONE; statusLabel.text = "✦ AI 回覆助理"
            render(result)
        }
    }

    private fun callLlm(chat: String, pkg: String, cal: String): Ai {
        val app = mapOf("com.tencent.mm" to "WeChat","com.linecorp.line" to "LINE",
            "jp.naver.line.android" to "LINE","org.telegram.messenger" to "Telegram",
            "com.whatsapp" to "WhatsApp","com.facebook.orca" to "Messenger",
            "com.instagram.android" to "Instagram","com.discord" to "Discord")[pkg] ?: "Chat"
        val sys = """你是智慧回覆助理。日曆：$cal
輸出嚴格JSON（不含markdown）：{"replies":["回覆1","回覆2","回覆3"],"actions":[]}
actions格式：{"type":"add_alarm","time":"HH:mm","label":""}或{"type":"add_calendar","title":"","date":"yyyy-MM-dd","time":"HH:mm"}
僅在明確提到時間/行程時才填actions，否則[]。replies語言跟對話一致，簡短自然。"""
        val body = JSONObject().apply {
            put("messages", JSONArray().apply {
                put(JSONObject().put("role","system").put("content",sys))
                put(JSONObject().put("role","user").put("content","$app 對話：\n$chat"))
            })
            put("max_tokens", prefs.getInt("max_tokens",256))
            put("temperature",0.75); put("stream",false)
        }.toString()
        val url = prefs.getString("server_url","http://127.0.0.1:8080") + "/v1/chat/completions"
        return runCatching {
            val req = Request.Builder().url(url).post(body.toRequestBody("application/json".toMediaType())).build()
            val txt = http.newCall(req).execute().body?.string() ?: return fallback()
            val json = JSONObject(txt)
            val choices = json.optJSONArray("choices") ?: return fallback()
            if (choices.length() == 0) return fallback()
            val choice = choices.optJSONObject(0) ?: return fallback()
            val message = choice.optJSONObject("message") ?: return fallback()
            val content = message.optString("content", "").trim()
            if (content.isEmpty()) return fallback()
            parseAi(content)
        }.getOrElse { fallback() }
    }

    private fun parseAi(json: String): Ai {
        return runCatching {
            val o = JSONObject(json)
            val rep = (0 until o.getJSONArray("replies").length()).map { o.getJSONArray("replies").getString(it) }
            val acts = mutableListOf<Act>()
            o.optJSONArray("actions")?.let { arr ->
                for (i in 0 until arr.length()) {
                    val a = arr.getJSONObject(i)
                    acts.add(Act(a.getString("type"),a.optString("title"),a.optString("date"),a.optString("time"),a.optString("label")))
                }
            }
            Ai(rep, acts)
        }.getOrElse { fallback() }
    }
    private fun fallback() = Ai(listOf("好的","收到！","了解 👍"), emptyList())

    private fun render(ai: Ai) {
        chipRow.removeAllViews(); actionRow.removeAllViews()
        val colors = listOf(0x26A78BFA,0x261E40FF,0x26818CF8)
        val borders = listOf(0x4DA78BFA,0x4D1E40FF,0x4D818CF8)
        val textClrs= listOf(0xCCA78BFA,0xCC94A3F8.toInt(),0xCC818CF8.toInt())
        val dp = resources.displayMetrics.density; fun Int.dp()=(this*dp).toInt()
        ai.replies.forEachIndexed { i, reply ->
            val tv = TextView(this).apply {
                text = reply; textSize = 13.5f
                setTextColor(textClrs.getOrElse(i){0xCCFFFFFF.toInt()})
                setPadding(16.dp(),10.dp(),16.dp(),10.dp())
                background = rounded(colors.getOrElse(i){0x26FFFFFF},borders.getOrElse(i){0x33FFFFFF},18.dp().toFloat())
                layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,ViewGroup.LayoutParams.WRAP_CONTENT).apply{topMargin=5.dp()}
                maxLines=3; ellipsize=android.text.TextUtils.TruncateAt.END
                setOnClickListener { copyText(reply); pulse(this) }
            }
            chipRow.addView(tv)
            tv.alpha=0f; tv.translationY=12f
            tv.animate().alpha(1f).translationY(0f).setStartDelay((i*60).toLong()).setDuration(220).setInterpolator(DecelerateInterpolator()).start()
        }
        actionRow.visibility = if(ai.actions.isEmpty()) View.GONE else View.VISIBLE
        ai.actions.forEachIndexed { i, act ->
            val (em,lbl) = when(act.type) {
                "add_calendar" -> "📅" to "加入日曆：${act.title} ${act.date} ${act.time}"
                "add_alarm"    -> "⏰" to "設定鬧鐘：${act.time} ${act.label}"
                else -> "▶" to act.type
            }
            val row = LinearLayout(this).apply {
                orientation=LinearLayout.HORIZONTAL; gravity=Gravity.CENTER_VERTICAL
                setPadding(14.dp(),10.dp(),14.dp(),10.dp())
                background=rounded(0x20FFD700,0x40FFD700,16.dp().toFloat())
                layoutParams=LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,ViewGroup.LayoutParams.WRAP_CONTENT).apply{topMargin=5.dp()}
                addView(TextView(context).apply{text=em;textSize=16f;setPadding(0,0,10.dp(),0)})
                addView(TextView(context).apply{text=lbl;textSize=12.5f;setTextColor(0xCCFFD700.toInt())
                    layoutParams=LinearLayout.LayoutParams(0,ViewGroup.LayoutParams.WRAP_CONTENT,1f)})
                setOnClickListener{doAction(act)}
            }
            actionRow.addView(row)
            row.alpha=0f; row.animate().alpha(1f).setStartDelay(((ai.replies.size+i)*60).toLong()).setDuration(200).start()
        }
    }

    private fun rounded(fill:Int,stroke:Int,r:Float)=android.graphics.drawable.GradientDrawable().apply{
        shape=android.graphics.drawable.GradientDrawable.RECTANGLE;cornerRadius=r;setColor(fill);setStroke(1,stroke)
    }
    private fun updatePos() {
        if (inputTop<=0) return
        params.y = screenH - inputTop + (8*resources.displayMetrics.density).toInt()
        if (root.isAttachedToWindow) runCatching { wm.updateViewLayout(root,params) }
    }
    private fun show() {
        if (root.visibility==View.VISIBLE) return
        root.visibility=View.VISIBLE; root.alpha=0f; root.translationY=30f
        root.animate().alpha(1f).translationY(0f).setDuration(250).setInterpolator(DecelerateInterpolator(1.5f)).start()
    }
    private fun hide() {
        root.animate().alpha(0f).translationY(20f).setDuration(180).setInterpolator(AccelerateInterpolator())
            .withEndAction{root.visibility=View.GONE}.start()
    }
    private fun toggleExpand() {
        isExpanded=!isExpanded
        if (isExpanded) {
            contentArea.visibility=View.VISIBLE
            contentArea.measure(View.MeasureSpec.UNSPECIFIED,View.MeasureSpec.UNSPECIFIED)
            val h=contentArea.measuredHeight
            ValueAnimator.ofInt(0,h).apply{duration=220;interpolator=DecelerateInterpolator()
                addUpdateListener{contentArea.layoutParams.height=it.animatedValue as Int;contentArea.requestLayout()}
                addListener(object:AnimatorListenerAdapter(){override fun onAnimationEnd(a:Animator){contentArea.layoutParams.height=ViewGroup.LayoutParams.WRAP_CONTENT}})
            }.start()
        } else {
            val h=contentArea.height
            ValueAnimator.ofInt(h,0).apply{duration=180
                addUpdateListener{contentArea.layoutParams.height=it.animatedValue as Int;contentArea.requestLayout()}
                addListener(object:AnimatorListenerAdapter(){override fun onAnimationEnd(a:Animator){contentArea.visibility=View.GONE}})
            }.start()
        }
    }
    private fun pulse(v: View) {
        ObjectAnimator.ofPropertyValuesHolder(v,
            PropertyValuesHolder.ofFloat("scaleX",1f,.96f,1f),
            PropertyValuesHolder.ofFloat("scaleY",1f,.96f,1f)
        ).apply{duration=150;interpolator=DecelerateInterpolator()}.start()
        if (Build.VERSION.SDK_INT>=Build.VERSION_CODES.Q)
            getSystemService(Vibrator::class.java)?.vibrate(VibrationEffect.createPredefined(VibrationEffect.EFFECT_CLICK))
    }
    private fun copyText(t:String) {
        (getSystemService(ClipboardManager::class.java)).setPrimaryClip(ClipData.newPlainText("r",t))
        Toast.makeText(this,"✓ 已複製",Toast.LENGTH_SHORT).show()
    }
    private fun doAction(a:Act) { when(a.type){"add_alarm"->addAlarm(a);"add_calendar"->addCal(a)} }
    private fun addAlarm(a:Act) {
        val p=a.time.split(":").mapNotNull{it.toIntOrNull()}
        startActivity(Intent(AlarmClock.ACTION_SET_ALARM).apply{
            putExtra(AlarmClock.EXTRA_HOUR,p.getOrElse(0){8});putExtra(AlarmClock.EXTRA_MINUTES,p.getOrElse(1){0})
            putExtra(AlarmClock.EXTRA_MESSAGE,a.label.ifBlank{"助理鬧鐘"});putExtra(AlarmClock.EXTRA_SKIP_UI,true)
            flags=Intent.FLAG_ACTIVITY_NEW_TASK
        })
        Toast.makeText(this,"⏰ 已設定鬧鐘 ${a.time}",Toast.LENGTH_SHORT).show()
    }
    private fun addCal(a:Act) {
        runCatching {
            val sdf=SimpleDateFormat("yyyy-MM-dd HH:mm",Locale.getDefault())
            val s=sdf.parse("${a.date} ${a.time}")?.time?:(System.currentTimeMillis()+3600000)
            contentResolver.insert(CalendarContract.Events.CONTENT_URI, android.content.ContentValues().apply{
                put(CalendarContract.Events.TITLE,a.title);put(CalendarContract.Events.DTSTART,s)
                put(CalendarContract.Events.DTEND,s+3600000);put(CalendarContract.Events.CALENDAR_ID,defCal())
                put(CalendarContract.Events.EVENT_TIMEZONE,TimeZone.getDefault().id)
            })
            Toast.makeText(this,"📅 已加入日曆：${a.title}",Toast.LENGTH_SHORT).show()
        }.onFailure {
            startActivity(Intent(Intent.ACTION_INSERT).apply{
                data=CalendarContract.Events.CONTENT_URI;putExtra(CalendarContract.Events.TITLE,a.title)
                flags=Intent.FLAG_ACTIVITY_NEW_TASK
            })
        }
    }
    private fun defCal():Long {
        return contentResolver.query(CalendarContract.Calendars.CONTENT_URI,
            arrayOf(CalendarContract.Calendars._ID),"${CalendarContract.Calendars.IS_PRIMARY}=1",null,null)
            ?.use{if(it.moveToFirst())it.getLong(0) else 1L}?:1L
    }
    private fun calCtx():String {
        return runCatching {
            val c=contentResolver.query(CalendarContract.Events.CONTENT_URI,
                arrayOf(CalendarContract.Events.TITLE,CalendarContract.Events.DTSTART),
                "${CalendarContract.Events.DTSTART}>=?", arrayOf(System.currentTimeMillis().toString()),
                "${CalendarContract.Events.DTSTART} ASC")
            val l=mutableListOf<String>(); var n=0
            c?.use{while(it.moveToNext()&&n<4){l.add(SimpleDateFormat("MM/dd HH:mm",Locale.getDefault()).format(Date(it.getLong(1)))+" "+it.getString(0));n++}}
            if(l.isEmpty())"無近期行程" else l.joinToString("；")
        }.getOrDefault("")
    }
    private fun notif() {
        val ch="ca"; val nm=getSystemService(NotificationManager::class.java)
        if(nm.getNotificationChannel(ch)==null)
            nm.createNotificationChannel(NotificationChannel(ch,"Chat Assistant",NotificationManager.IMPORTANCE_MIN))
        startForeground(42,NotificationCompat.Builder(this,ch)
            .setContentTitle("Chat Assistant").setContentText("AI 回覆助理運行中")
            .setSmallIcon(android.R.drawable.ic_dialog_info).setOngoing(true).build())
    }
}
KT

cat > "$PROJ_DIR/app/src/main/kotlin/com/chatassistant/BootReceiver.kt" << 'KT'
package com.chatassistant
import android.content.BroadcastReceiver; import android.content.Context; import android.content.Intent
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, i: Intent) {
        if (i.action == Intent.ACTION_BOOT_COMPLETED)
            ctx.startForegroundService(Intent(ctx, FloatingService::class.java).apply{action="START"})
    }
}
KT

log "Kotlin 原始碼完成"

# ───────────────────────────── 6. 安裝 Gradle ─────────────────────────────
step "安裝 Gradle Wrapper"
GRADLE_BIN="$HOME_DIR/.gradle/wrapper/dists/gradle-8.4-bin"
if ! command -v gradle &>/dev/null; then
    warn "用 pkg 安裝 gradle..."
    pkg install -y gradle 2>/dev/null || true
fi
if ! command -v gradle &>/dev/null; then
    warn "pkg 無 gradle，手動下載 Gradle 8.4..."
    GRADLE_ZIP="$HOME_DIR/gradle.zip"
    wget -q --show-progress \
        "https://services.gradle.org/distributions/gradle-8.4-bin.zip" \
        -O "$GRADLE_ZIP"
    mkdir -p "$HOME_DIR/.local"
    unzip -q "$GRADLE_ZIP" -d "$HOME_DIR/.local/"
    rm -f "$GRADLE_ZIP"
    export PATH="$HOME_DIR/.local/gradle-8.4/bin:$PATH"
fi
command -v gradle &>/dev/null || die "gradle 安裝失敗，請手動執行：pkg install gradle"
log "系統 Gradle 版本：$(gradle --version 2>/dev/null | grep Gradle | head -1)"

cd "$PROJ_DIR"
gradle wrapper --gradle-version=8.4 --distribution-type=bin --no-daemon 2>/dev/null || true
if [ -f "$PROJ_DIR/gradle/wrapper/gradle-wrapper.properties" ]; then
    sed -i 's|distributionUrl=.*|distributionUrl=https\://services.gradle.org/distributions/gradle-8.4-bin.zip|' \
        "$PROJ_DIR/gradle/wrapper/gradle-wrapper.properties"
fi
chmod +x "$PROJ_DIR/gradlew"
log "Gradle 就緒"

# ───────────────────────────── 7. 編譯 APK ─────────────────────────────
step "編譯 APK"
cd "$PROJ_DIR"
export GRADLE_OPTS="-Xmx2g -Dorg.gradle.daemon=false -Dorg.gradle.jvmargs=-Xmx2g"

LOG="$HOME_DIR/build_error.log"
./gradlew assembleRelease --no-daemon --stacktrace 2>&1 | tee "$LOG" | grep -E "^e:|error:|Error:|FAILED|Exception|warning:" | head -60
tail -20 "$LOG"

if [ ! -f "$APK_OUT" ]; then
    warn "Release 失敗，查看完整錯誤：cat ~/build_error.log"
    warn "嘗試 debug build..."
    LOG_D="$HOME_DIR/build_debug.log"
    ./gradlew assembleDebug --no-daemon --stacktrace 2>&1 | tee "$LOG_D" | grep -E "^e:|error:|Error:|FAILED|Exception" | head -60
    tail -20 "$LOG_D"
    APK_OUT=$(find "$PROJ_DIR/app/build" -name "*.apk" 2>/dev/null | head -1)
fi
[ -f "$APK_OUT" ] || die "APK 編譯失敗，查看上方錯誤訊息"
log "APK 編譯成功：$APK_OUT"

# ───────────────────────────── 8. 對齊 + 複製 APK ─────────────────────────
step "處理 APK"
ZIPALIGN="$SDK_DIR/build-tools/34.0.0/zipalign"
if [ -f "$ZIPALIGN" ]; then
    "$ZIPALIGN" -v 4 "$APK_OUT" "$APK_SIGNED" 2>/dev/null && log "zipalign 完成" || cp "$APK_OUT" "$APK_SIGNED"
else
    cp "$APK_OUT" "$APK_SIGNED"
fi
log "APK 位置：$APK_SIGNED"

# ───────────────────────────── 9. 安裝 APK (KernelSU root) ─────────────
step "安裝 APK（需 root）"
if su -c "pm install -r '$APK_SIGNED'" 2>/dev/null; then
    log "APK 安裝成功！"
    PKG="com.chatassistant"
    su -c "appops set $PKG SYSTEM_ALERT_WINDOW allow"
    su -c "appops set $PKG READ_CALENDAR allow"
    su -c "appops set $PKG WRITE_CALENDAR allow"
    su -c "pm grant $PKG android.permission.READ_CALENDAR" 2>/dev/null || true
    su -c "pm grant $PKG android.permission.WRITE_CALENDAR" 2>/dev/null || true
    su -c "pm grant $PKG android.permission.READ_CONTACTS" 2>/dev/null || true
    su -c "dumpsys deviceidle whitelist +com.termux" 2>/dev/null || true
    su -c "dumpsys deviceidle whitelist +$PKG" 2>/dev/null || true
    log "權限授予完成"
else
    warn "自動安裝失敗，請手動安裝：$APK_SIGNED"
fi

# ───────────────────────────── 10. llama-server 啟動腳本 ─────────────────
step "設定 llama-server 自動啟動"
cat > "$HOME_DIR/start_llm.sh" << LLMSH
#!/data/data/com.termux/files/usr/bin/bash
MODEL="$MODEL_FILE"
SERVER="$LLM_DIR/build/bin/llama-server"

if [ ! -f "\$MODEL" ]; then
    echo "❌ 模型不存在：\$MODEL"
    exit 1
fi

echo "🚀 啟動 llama-server (Gemma 2B Q4_K_M)..."
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

mkdir -p "$HOME_DIR/.termux/boot"
cat > "$HOME_DIR/.termux/boot/start_assistant.sh" << BOOT
#!/data/data/com.termux/files/usr/bin/bash
sleep 10
termux-wake-lock
bash $HOME_DIR/start_llm.sh &
BOOT
chmod +x "$HOME_DIR/.termux/boot/start_assistant.sh"
log "開機自啟設定完成（需安裝 Termux:Boot）"

echo -e "
${CYN}╔══════════════════════════════════════════╗
║   🎉 全部完成！                          ║
╠══════════════════════════════════════════╣
║                                          ║
║  APK：~/ChatAssistant.apk               ║
║                                          ║
║  後續步驟：                              ║
║  1. 開啟 Chat Assistant APP              ║
║  2. 點「授予浮動視窗權限」               ║
║  3. 點「開啟無障礙服務」並啟用           ║
║  4. 執行：bash ~/start_llm.sh           ║
║  5. APP 點「啟動助理服務」               ║
║  6. 打開 LINE/微信/Instagram/Messenger/WhatsApp/Telegram 開始聊天 ✨
║                                          ║
║  模型位置：~/models/gemma-2-2b-it-Q4_K_M.gguf
╚══════════════════════════════════════════╝${NC}"