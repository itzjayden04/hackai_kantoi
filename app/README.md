# Kantoi app (Flutter, Android)

Source of the Kantoi Android app. See the [main README](../README.md) for what it does, how to install it and the demo script.

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release --dart-define=GEMINI_API_KEY=...
```

- `lib/engine/` scam checks, link forensics, web search, trace and reports
- `lib/intake/` reading messages, screenshots, files, QR codes and chat exports
- `lib/guard/` phone protection (notification, accessibility, call, site, app and picture guards)
- `lib/ui/` screens; design tokens in `lib/ui/theme.dart`, shared widgets in `lib/ui/kit.dart`
- `android/app/src/main/kotlin/` native services for phone protection
