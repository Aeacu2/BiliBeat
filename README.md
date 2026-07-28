# BiliBeat

A Flutter music player for Bilibili audio with synced LRC lyrics and offline caching.

## Downloads

- [Latest Release](https://github.com/Aeacu2/BiliBeat/releases/latest)

## Signing

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
tool/build_release.sh
```

Builds a single obfuscated **arm64-v8a** APK. 32-bit is dropped permanently;
ARM laptops (Apple Silicon, Windows on ARM) use arm64-v8a too, so this one
build covers them.

Requires **JDK 21+** — AGP's lint fails on JDK 17 with an unrelated-looking
`NoSuchMethodError`.

Obfuscation means crash traces from a shipped build are unreadable without that
build's symbol files, written to `symbols/<version>/`. Keep them (attach them to
the release) and decode with:

```bash
flutter symbolize -i trace.txt -d symbols/<version>/app.android-arm64.symbols
```

## License

MIT
