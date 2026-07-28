# BiliBeat (哔哩节奏) 🎵

> 极其优雅、极简、高保真的 B 站音频播放与歌词同频工具。支持无缝离线下载、自动精准歌词匹配与 Apple Music 风格动态渐变视觉。

---

## 📦 下载安装 (Downloads)

### 📱 Android 推荐版本

- ⚡ **[下载 Android ARM64-v8a 64位优化版 APK (20.3 MB)](build/app/outputs/flutter-apk/app-arm64-v8a-release.apk)**  
  *(适用于 99%+ 现代 Android 手机与平板，体积相比通用版缩小 63%)*

### 对应架构下载列表

| 平台 / 架构 | 设备类型 | APK 文件路径 / 下载链接 | 大小 |
| :--- | :--- | :--- | :--- |
| **Android ARM 64-bit** | 99%+ 现代 Android 手机 | [app-arm64-v8a-release.apk](build/app/outputs/flutter-apk/app-arm64-v8a-release.apk) | **20.3 MB** |
| **Android ARM 32-bit** | 早期 32 位 Android 设备 | [app-armeabi-v7a-release.apk](build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk) | **17.7 MB** |
| **Android x86 64-bit** | Android 模拟器 / Intel 设备 | [app-x86_64-release.apk](build/app/outputs/flutter-apk/app-x86_64-release.apk) | **21.8 MB** |
| **Universal (通用版)** | 包含所有 CPU 架构的全量包 | [app-release.apk](build/app/outputs/flutter-apk/app-release.apk) | 55.4 MB |

---

## ✨ 核心特性 (Key Features)

- 🎧 **高保真音频提取**：支持 B 站视频 / 分 P 原声音频提取，优先匹配标准 AAC/M4A 及 320k DASH 音轨。
- 🎤 **智能逐词/逐句歌词**：自动清洗视频标题（过滤 `《...》` 书名号、UP主标签、现场日期及画质标识），联网智能匹配网易云 / LRCLIB 动态 LRC 歌词。
- 🎨 **Apple Music 视觉美学**：根据专辑封面实时提取全屏沉浸式高斯模糊动态背景，搭配流光跑马灯与流畅微交互。
- ⬇️ **全自动离线下载**：一键下载至本地存储，带有 Apple Music 风格环形进度条 (`ProgressRing`)，无网络环境随时播放。
- 📜 **歌词与信息校准**：支持时间轴毫秒级偏移调整、自定义 LRC 文本粘贴、以及从手机相册自定义封面。

---

## 🛠️ 技术栈与工具链 (Tech Stack)

- **UI 框架**: Flutter 3.44.8 Stable
- **Android Target**: Android 16 (API 36), Android NDK 28.2
- **构建工具**: Gradle 9.5.1, Android Gradle Plugin (AGP) 9.3.1
- **运行环境**: OpenJDK 26 (`openjdk@26`), Built-in Kotlin 2.4.10
- **macOS 构建**: Swift Package Manager (SPM) 原生集成
- **音频引擎**: `just_audio` 0.10.6 + `audio_service` 0.18.19 (背景播放与系统 MediaSession)

---

## 🚀 本地构建 (Building from Source)

### 克隆项目
```bash
git clone https://github.com/Aeacu2/bilibeat.git
cd bilibeat
```

### 构建 Android Release APK (按 CPU 架构分包)
```bash
flutter build apk --split-per-abi --release
```
编译产物位于 `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`。

### 运行 macOS 原生应用
```bash
flutter run -d macos
```

---

## 📄 License
MIT License.
