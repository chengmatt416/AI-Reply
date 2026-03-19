# AI-Reply — Chat Assistant

A local AI reply assistant for Android that overlays AI-generated reply suggestions on top of your chat apps (WeChat, LINE, Telegram, WhatsApp, Messenger, Instagram, Discord).

## Features

- Floating overlay with AI-generated reply suggestions
- Uses a local LLM server (llama.cpp compatible)
- Supports WeChat, LINE, Telegram, WhatsApp, Messenger, Instagram, Discord
- Calendar integration for scheduling actions
- Alarm integration

## Download the Debug APK

The latest debug APK is automatically built by GitHub Actions on every push to `main`.

1. Go to the **[Actions](../../actions)** tab of this repository.
2. Click on the latest **build-android-apk** workflow run.
3. Scroll down to **Artifacts** and download **app-debug-apk**.
4. Unzip and install `app-debug.apk` on your Android device (Android 12+ / API 31+).

> **Note:** You need to enable "Install from unknown sources" on your device to sideload the APK.

## Setup

1. Install and start a compatible LLM server (e.g. [llama.cpp](https://github.com/ggerganov/llama.cpp)) on your device or local network.
2. Open the Chat Assistant app and:
   - Grant **Overlay (floating window) permission**
   - Enable the **Accessibility Service** in Android settings
   - Set the **LLM server URL** (default: `http://127.0.0.1:8080`)
   - Tap **Start Service**
3. Open a supported chat app and the AI overlay will appear automatically.

## Build Locally

Requirements: JDK 17, Android SDK with build-tools 34.

```bash
./gradlew assembleDebug
# Output: app/build/outputs/apk/debug/app-debug.apk
```

## Accessibility Service

The app declares a `ChatAccessibilityService` that reads chat message content to generate reply suggestions. This service must be enabled by the user manually in **Settings → Accessibility** — it is never auto-started or started via `startService`. It is declared with `android.permission.BIND_ACCESSIBILITY_SERVICE` as required by Android.
