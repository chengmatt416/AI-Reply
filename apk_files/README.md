# ChatAssistant APK Build Files

This directory contains all the necessary files to build the ChatAssistant Android app and set up the llama-server in Termux.

## Contents

- `extract_apk_files.sh` - Extracts Android project structure and resource files
- `create_kotlin_files.sh` - Creates all Kotlin source code files
- `build_apk.sh` - Builds the APK file
- `setup_server.sh` - Sets up and starts the llama-server
- `test_server.sh` - Tests the llama-server

## Requirements

This is designed to run on **Termux** with the following:
- Android device (preferably with KernelSU or root access)
- Termux app installed
- At least 4GB of free storage
- Internet connection for downloading dependencies

## Quick Start

### Step 1: Extract APK Files

```bash
cd ~/apk_files
bash extract_apk_files.sh
bash create_kotlin_files.sh
```

This will create the complete Android project structure in `~/ChatAssistant/`

### Step 2: Install Prerequisites

Make sure you have Java and Android SDK installed:

```bash
pkg update
pkg install openjdk-17 wget unzip git cmake clang ninja python
```

You'll also need Android SDK cmdline-tools. The build script will guide you through this if needed.

### Step 3: Build the APK

```bash
bash build_apk.sh
```

This will:
- Set up the Android SDK (if needed)
- Set up Gradle
- Build the APK
- Install it (if you have root access)
- Grant necessary permissions

The compiled APK will be saved to `~/ChatAssistant.apk`

### Step 4: Setup the Server

```bash
bash setup_server.sh
```

This will:
- Install dependencies
- Clone and build llama.cpp
- Download the Gemma 2B model (~1.6GB)
- Create startup scripts
- Start the server automatically

### Step 5: Test the Server

```bash
bash test_server.sh
```

This will verify that:
- The server is running
- Endpoints are responding
- AI responses are being generated correctly

## Usage

After completing all steps:

1. Open the **Chat Assistant** app on your Android device
2. Grant the requested permissions:
   - Floating window permission
   - Accessibility service permission
3. The app will check the server status
4. Start using it in supported messaging apps:
   - WeChat (微信)
   - LINE
   - Instagram
   - Telegram
   - WhatsApp
   - Facebook Messenger
   - Discord

## Server Management

### Start the server:
```bash
bash ~/start_llm.sh
```

### Stop the server:
```bash
kill $(cat ~/llama_server.pid)
```

### View logs:
```bash
tail -f ~/llama_server.log
```

### Check server status:
```bash
curl http://127.0.0.1:8080/health
```

## Troubleshooting

### Build fails:
- Check that you have enough memory (at least 2GB free)
- Make sure Android SDK is properly installed
- View build logs: `cat ~/build_log.log`

### Server fails to start:
- Check system resources (at least 2GB RAM recommended)
- View server logs: `cat ~/llama_server.log`
- Make sure port 8080 is not in use

### App doesn't detect messages:
- Verify accessibility service is enabled
- Check that floating window permission is granted
- Restart the app and the accessibility service

## File Structure

```
~/ChatAssistant/                    # Android project root
├── app/
│   ├── src/main/
│   │   ├── kotlin/com/chatassistant/
│   │   │   ├── MainActivity.kt
│   │   │   ├── ChatAccessibilityService.kt
│   │   │   ├── FloatingService.kt
│   │   │   └── BootReceiver.kt
│   │   ├── res/
│   │   │   ├── layout/
│   │   │   ├── values/
│   │   │   ├── xml/
│   │   │   └── drawable/
│   │   └── AndroidManifest.xml
│   └── build.gradle.kts
├── gradle/
├── settings.gradle.kts
├── build.gradle.kts
└── local.properties

~/llama.cpp/                        # llama.cpp source
└── build/bin/llama-server         # Compiled server binary

~/models/                           # AI models
└── gemma-2-2b-it-Q4_K_M.gguf     # Gemma 2B model (1.6GB)

~/start_llm.sh                      # Server startup script
~/.termux/boot/start_assistant.sh   # Auto-start script
```

## Features

The ChatAssistant app provides:
- **Smart reply suggestions** based on chat context
- **Calendar integration** for scheduling
- **Alarm integration** for reminders
- **Multiple chat app support**
- **Local AI processing** (no internet needed after setup)
- **Privacy-focused** (all data stays on device)

## Model Information

- **Model**: Gemma 2B (Instruct, Q4_K_M quantization)
- **Size**: ~1.6GB
- **Performance**: Optimized for ARM devices
- **Language**: Primarily English and Chinese

## License

This project uses:
- llama.cpp (MIT License)
- Gemma model (Google's terms)
- Android Open Source Project (Apache 2.0)

## Credits

Based on the build_all-3_Version5.sh script for the ChatAssistant project.
