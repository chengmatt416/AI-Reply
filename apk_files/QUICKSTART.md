# ChatAssistant APK Files - Quick Reference

## Overview

This directory contains modularized scripts extracted from `build_all-3_Version5.sh` to build a ChatAssistant Android app with local AI capabilities.

## Files Created

### Main Scripts (run in order):
1. **extract_apk_files.sh** (25KB)
   - Creates Android project structure
   - Generates Gradle configuration files
   - Creates resource files (XML layouts, themes, drawables)
   - Creates AndroidManifest.xml
   - Generates app icon

2. **create_kotlin_files.sh** (28KB)
   - Creates MainActivity.kt
   - Creates ChatAccessibilityService.kt
   - Creates FloatingService.kt
   - Creates BootReceiver.kt

3. **build_apk.sh** (4.7KB)
   - Sets up Android SDK environment
   - Configures Gradle
   - Builds the APK
   - Signs and aligns the APK
   - Installs APK with root
   - Grants permissions

4. **setup_server.sh** (6.1KB)
   - Installs dependencies
   - Clones and builds llama.cpp
   - Downloads Gemma 2B model
   - Creates startup scripts
   - Starts the server
   - Sets up auto-start on boot

5. **test_server.sh** (5.7KB)
   - Tests health endpoint
   - Tests chat completions
   - Tests ChatAssistant format
   - Shows server performance
   - Validates responses

### Convenience Scripts:
- **setup_all.sh** - Runs all steps in order with progress tracking

### Documentation:
- **README.md** - Complete documentation with troubleshooting
- **QUICKSTART.md** - This file

## Quick Start

### Option 1: Full Automated Setup
```bash
cd ~/apk_files
bash setup_all.sh
```

### Option 2: Step-by-Step
```bash
cd ~/apk_files

# Step 1: Extract project files
bash extract_apk_files.sh
bash create_kotlin_files.sh

# Step 2: Build APK
bash build_apk.sh

# Step 3: Setup server
bash setup_server.sh

# Step 4: Test server
bash test_server.sh
```

## Prerequisites

### Required:
- Termux installed on Android
- 4GB free storage minimum
- Internet connection (for downloads)
- Android API 31+ device

### Recommended:
- Root access (KernelSU) for auto-installation
- 8GB RAM or more
- Fast internet for downloads

## What Gets Created

```
~/ChatAssistant/              # Android project (extracted)
  ├── app/src/main/
  │   ├── kotlin/...
  │   ├── res/...
  │   └── AndroidManifest.xml
  ├── gradle/...
  └── build.gradle.kts

~/ChatAssistant.apk          # Built APK (~8-12MB)

~/llama.cpp/                 # llama.cpp source
  └── build/bin/llama-server # Server binary

~/models/                    # AI models
  └── gemma-2-2b-it-Q4_K_M.gguf  # ~1.6GB

~/start_llm.sh              # Server startup script
~/llama_server.log          # Server logs
~/llama_server.pid          # Server PID
~/.termux/boot/             # Auto-start scripts
```

## Downloads Required

- Android SDK cmdline-tools: ~130MB
- Android build-tools + platform: ~400MB
- Gemma 2B model: ~1.6GB
- **Total**: ~2.1GB

## Time Estimates

- Extract files: 1-2 minutes
- Build APK: 5-15 minutes (depends on device)
- Setup server: 10-30 minutes (depends on internet)
- **Total**: 15-45 minutes

## After Setup

1. Open **Chat Assistant** app
2. Grant required permissions
3. Start the assistant service
4. Open any supported messaging app
5. AI suggestions will appear automatically

## Supported Apps

- WeChat (微信)
- LINE
- Instagram Direct Messages
- Telegram
- WhatsApp
- Facebook Messenger
- Discord

## Troubleshooting

### "Permission denied"
```bash
chmod +x *.sh
```

### "Server not responding"
```bash
bash ~/start_llm.sh
tail -f ~/llama_server.log
```

### "APK build failed"
```bash
cat ~/build_log.log
```

### "Out of memory"
- Close other apps
- Free up storage space
- Reboot device and try again

## Server Management

```bash
# Start server
bash ~/start_llm.sh

# Stop server
kill $(cat ~/llama_server.pid)

# Check status
curl http://127.0.0.1:8080/health

# View logs
tail -f ~/llama_server.log

# Test server
bash ~/apk_files/test_server.sh
```

## Key Features

✅ **Local Processing** - All AI runs on device
✅ **Privacy First** - No data sent to cloud
✅ **Multi-App Support** - Works with 8 chat apps
✅ **Smart Replies** - Context-aware suggestions
✅ **Calendar Integration** - Automatic scheduling
✅ **Lightweight** - Only 1.6GB model size

## Technical Details

- **Build System**: Gradle 8.4
- **Android SDK**: API 34
- **Kotlin Version**: 1.9.22
- **Min SDK**: API 31 (Android 12)
- **AI Model**: Gemma 2B Q4_K_M
- **Server**: llama.cpp with OpenAI-compatible API
- **Optimization**: ARM v9-a with SIMD instructions

## Credits

Based on the original `build_all-3_Version5.sh` script.

## License

See individual component licenses:
- llama.cpp: MIT
- Gemma: Google terms
- Android components: Apache 2.0
