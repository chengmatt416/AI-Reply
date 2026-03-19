#!/data/data/com.termux/files/usr/bin/bash
# ════════════════════════════════════════════════════════════════════
#  APK File Extraction Script
#  Extracts all Android project files needed to build the ChatAssistant APK
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

step "Creating Android project structure"
rm -rf "$PROJ_DIR"
mkdir -p "$PROJ_DIR"/{app/src/main/{kotlin/com/chatassistant,res/{layout,values,xml,drawable,mipmap-hdpi}},gradle/wrapper}
log "Project structure created"

step "Creating Gradle configuration files"

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
fi

log "Gradle configuration complete"

step "Creating Android Manifest"

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

log "Android Manifest created"

step "Creating resource files"

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

log "Drawable resources created"

step "Creating app icon"
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

log "App icon generated"

step "Creating main layout"
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

log "Layout files created"

echo -e "${CYN}
╔════════════════════════════════════════════════╗
║   ✅ APK Files Extracted Successfully         ║
╠════════════════════════════════════════════════╣
║  Project Location: ~/ChatAssistant            ║
║                                                ║
║  Next Steps:                                   ║
║  1. Run: bash build_apk.sh                     ║
║     (to compile the APK)                       ║
║                                                ║
║  2. Run: bash setup_server.sh                  ║
║     (to setup and start llama-server)          ║
║                                                ║
║  3. Run: bash test_server.sh                   ║
║     (to test the server)                       ║
╚════════════════════════════════════════════════╝${NC}"
