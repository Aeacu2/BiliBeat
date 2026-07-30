# BiliBeat

A Flutter music player for Bilibili audio with synced LRC lyrics and offline caching.

## Downloads & Installation

- **[Latest Release](https://github.com/Aeacu2/BiliBeat/releases/latest)**

---

### Android Installation

1. Download `bilibeat-x.x.x-arm64-v8a.apk` from the Latest Release page.
2. Open the downloaded `.apk` file on your Android device (requires Android 6.0 or later).
3. If prompted, enable "Allow installation from unknown sources" in system settings to complete installation.

---

### iOS Installation

As BiliBeat is not distributed through the Apple App Store, release builds are provided as unsigned package archives (`bilibeat-x.x.x-unsigned.ipa`). iOS requires the package to be signed with a personal development certificate prior to installation (requires iOS 13.0 or later).

#### Option 1: Installation via AltStore (Recommended)

AltStore enables local package installation and automated background certificate renewals over Wi-Fi.

1. **Install AltServer**: Download and run AltServer on macOS or Windows from [altstore.io](https://altstore.io).
2. **Deploy AltStore to Device**:
   - Connect the iOS device to the computer via USB and confirm device trust.
   - Click the AltServer icon in the menu bar or system tray, select `Install AltStore`, and select the connected iOS device.
   - Authenticate with your Apple ID credentials to issue a free development certificate.
3. **Trust Provisioning Certificate**: On the iOS device, navigate to `Settings` > `General` > `VPN & Device Management`, locate your Apple ID under Developer App, and select `Trust`.
4. **Install BiliBeat**:
   - Download `bilibeat-x.x.x-unsigned.ipa` using Safari on the iOS device.
   - Open AltStore, navigate to `My Apps`, tap the `+` icon, and select the downloaded `.ipa` file.
   - *Automatic Renewal*: AltServer automatically refreshes the 7-day certificate over local Wi-Fi whenever the host computer is active on the same network.

#### Option 2: Installation via Sideloadly

Sideloadly provides a direct desktop utility for installing signed packages over USB.

1. **Install Sideloadly**: Download Sideloadly on macOS or Windows from [sideloadly.io](https://sideloadly.io).
2. **Deploy Package**:
   - Connect the iOS device to the computer via USB.
   - Launch Sideloadly and drag `bilibeat-x.x.x-unsigned.ipa` into the application window.
   - Enter your Apple ID in the `Apple Account` field and click `Start`.
3. **Trust Provisioning Certificate**: Once complete, navigate to `Settings` > `General` > `VPN & Device Management` on the iOS device and trust the certificate associated with your Apple ID.

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
