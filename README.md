# BiliBeat

A Flutter music player for Bilibili audio with synced LRC lyrics and offline caching.

## Downloads

- [Latest Release](https://github.com/Aeacu2/BiliBeat/releases/latest)

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
