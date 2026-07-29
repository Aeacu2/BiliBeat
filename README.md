# BiliBeat

A Flutter music player for Bilibili audio with synced LRC lyrics and offline caching.

## Downloads & Installation Guide

- 📦 **[Latest Release (v3.5.2)](https://github.com/Aeacu2/BiliBeat/releases/latest)**

---

### 🤖 Android 安装指南 (Android Installation Guide)

- **下载文件**：请从 Release 页面下载 `bilibeat-x.x.x-arm64-v8a.apk` 文件。
- **直接安装**：在 Android 设备上点击下载的 APK 文件，若提示“允许安装来自未知来源的应用”，开启允许后即可直接安装使用（支持 Android 6.0+）。

---

### 📱 iOS 安装与试用指南 (iOS Installation Guide)

由于本项目未提交至苹果 App Store，构建产物为未签名的 `.ipa` 文件（`bilibeat-x.x.x-unsigned.ipa`）。你可以通过以下两种安全便捷的个人签名方式安装至 iPhone（支持 iOS 13+）：

#### 方案一：AltStore 安装（推荐，支持 Wi-Fi 无线自动续签）

1. **安装 AltServer**：在电脑（Mac 或 Windows）访问 [AltStore 官网](https://altstore.io) 下载并运行 AltServer。
2. **安装 AltStore 到手机**：
   - 用数据线将 iPhone 连接至电脑，并确保电脑信任手机。
   - 点击电脑顶部/任务栏的 AltServer 图标，选择 `Install AltStore` 并选择你的 iPhone。
   - 输入你的 Apple ID 邮箱及密码（仅用于向苹果服务器申请免费测试签名），等待手机出现 AltStore 图标。
3. **手机端信任证书**：在 iPhone 打开 **设置 -> 通用 -> VPN 与设备管理**，找到你的 Apple ID 并点击 **信任**。
4. **安装 BiliBeat**：
   - 在 iPhone 的 Safari 浏览器中下载最新版 `bilibeat-x.x.x-unsigned.ipa`。
   - 打开 iPhone 上的 **AltStore** 应用，切换到 `My Apps` 标签页，点击左上角的 **`+`** 按钮。
   - 选择下载好的 IPA 文件即可完成安装。
   - *自动续期*：只要手机与电脑连在同一 Wi-Fi 环境下，AltStore 会在后台自动为您刷新 7 天证书，无需重复插电脑。

#### 方案二：Sideloadly 安装（简易单次拖拽安装）

1. **下载 Sideloadly**：电脑访问 [Sideloadly 官网](https://sideloadly.io) 下载并安装软件。
2. **一键拖拽安装**：
   - 用 USB 数据线将 iPhone 连接电脑。
   - 打开 Sideloadly，将下载好的 `bilibeat-x.x.x-unsigned.ipa` 文件直接拖拽至软件窗口中。
   - 在 `Apple Account` 输入框填入你的 Apple ID 邮箱，点击 **Start** 启动安装。
3. **手机信任证书**：安装完成后在 **设置 -> 通用 -> VPN 与设备管理** 中信任你的证书，即可从桌面启动应用。

## Signing (Android)

Release builds are signed with the key in `android/key.properties`. Create it
once:

```bash
tool/make_keystore.sh
```

Back up **both** `android/bilibeat-release.jks` and `android/key.properties`,
and never commit them (both are gitignored). Losing the keystore is
unrecoverable — a different key cannot update an existing install.

Without that file the build falls back to the debug key and warns; check what
you actually shipped with:

```bash
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

## Build

```bash
tool/build_release.sh          # android (default)
```

```bash
tool/build_release.sh ios
```

```bash
tool/build_release.sh all
```

**Android** — a single obfuscated **arm64-v8a** APK. 32-bit is dropped
permanently; ARM laptops (Apple Silicon, Windows on ARM) use arm64-v8a too, so
this one build covers them. Requires **JDK 21+** — AGP's lint fails on JDK 17
with an unrelated-looking `NoSuchMethodError`.

**iOS** — an obfuscated **unsigned .ipa** (`build/ios/ipa/`). There is no Apple
Developer account behind this app, so it is not on the App Store and cannot be:
install it with AltStore / Sideloadly / your own provisioning profile, which
signs it with your identity. Needs macOS with Xcode; iOS 13+.

iOS has **no CocoaPods**. Every plugin used here ships a `Package.swift`, so the
project is integrated through Swift Package Manager and `ios/Podfile` was
removed on purpose — a leftover Podfile makes the build fail with "CocoaPods not
installed" even though nothing needs it. If some future plugin is Pods-only,
regenerate the Podfile with `flutter create .` and note it here.

Obfuscation means crash traces from a shipped build are unreadable without that
build's symbol files, written to `symbols/<version>/`. Keep them (attach them to
the release) and decode with:

```bash
flutter symbolize -i trace.txt -d symbols/<version>/app.android-arm64.symbols
```

(iOS traces use the same directory: `app.ios-arm64.symbols`.)

## License

MIT
