# BiliBeat

A Flutter music player for Bilibili audio with synced LRC lyrics and offline caching.

## Downloads

- **[Android ARM64 APK (20.3 MB)](build/app/outputs/flutter-apk/app-arm64-v8a-release.apk)**

### Build Variants

| Architecture | Target Device | File Path | Size |
| :--- | :--- | :--- | :--- |
| **ARM64 (v8a)** | Modern Android phones | [app-arm64-v8a-release.apk](build/app/outputs/flutter-apk/app-arm64-v8a-release.apk) | 20.3 MB |
| **ARM32 (v7a)** | 32-bit Android devices | [app-armeabi-v7a-release.apk](build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk) | 17.7 MB |
| **x86_64** | Emulators / Intel devices | [app-x86_64-release.apk](build/app/outputs/flutter-apk/app-x86_64-release.apk) | 21.8 MB |
| **Universal** | Universal fat APK | [app-release.apk](build/app/outputs/flutter-apk/app-release.apk) | 55.4 MB |

## Features

- Search and play Bilibili audio tracks (AAC/M4A & 320k DASH)
- Automatic synced LRC lyrics matching (NetEase & LRCLIB)
- Local track caching and offline playback
- Custom playlists and favorites
- Lyric timing offset adjustment and editor
- Cross-platform support (Android & macOS)

## Tech Stack

- Framework: Flutter 3.44+
- Target: Android 16 (API 36), NDK 28, AGP 9.3.1, Gradle 9.5.1
- Runtime: OpenJDK 26 (`openjdk@26`), Built-in Kotlin 2.4.10
- Audio: `just_audio` 0.10.6, `audio_service` 0.18.19

## Build Instructions

```bash
# Build Android APKs (split per ABI)
flutter build apk --split-per-abi --release

# Run macOS desktop app
flutter run -d macos
```

## License

MIT
