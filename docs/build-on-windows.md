# Build Kantoi from source on a Windows PC

This makes the same `Kantoi-android.apk` that GitHub Actions builds, on your own computer. Allow about an hour the first time (mostly downloads), then a few minutes per build.

## 1. Install the tools (one time)

1. **Turn on Developer Mode.** Settings > System > For developers (Windows 11) or Settings > Update & Security > For developers (Windows 10) > **Developer Mode: On**. Flutter needs it to build apps that use plugins, and Kantoi uses several.
2. **Install Android Studio** from https://developer.android.com/studio with the default options. Open it once and finish the Setup Wizard (**Standard**). This installs the Android SDK and the Java runtime the build uses.
   - In Android Studio: **More Actions > SDK Manager > SDK Tools**, tick **Android SDK Command-line Tools (latest)**, then **Apply**.
3. **Install Flutter 3.47 or later** (CI uses **3.47.7**). Follow https://docs.flutter.dev/get-started/install (choose Windows, then Android):
   - Unzip it to a folder without spaces or special permissions, such as `C:\src\flutter`. Not `C:\Program Files`.
   - Add `C:\src\flutter\bin` to your **Path** (Start > "Edit environment variables for your account" > Path > Edit > New).
4. Open a **new** PowerShell window and run:
   ```powershell
   flutter --version
   flutter doctor --android-licenses   # type y to accept each licence
   flutter doctor
   ```
   `flutter doctor` should show a green tick for **Flutter** and **Android toolchain**. The Chrome, Visual Studio and Windows lines don't matter for Kantoi.

## 2. Add your keys (optional)

Without keys the app builds and works on its built-in checks only. To switch on the online checks:

1. Copy `app\secrets.example.json` to `app\secrets.json`.
2. Fill in the keys you have and leave the rest as `""`. The names are the same as the GitHub secrets in the README, except the backup Gemini key: the GitHub secret `KANTOI_1` goes into `GEMINI_API_KEY_2` here.

`secrets.json` is in `.gitignore`. Never commit it.

**Firebase (online accounts and the shared scam database):** fill in `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_PROJECT_ID` and `FIREBASE_SENDER_ID` from `google-services.json`, as shown in [Connect Kantoi to Firebase](firebase-setup.md). Leave them empty to keep accounts on the phone.

> **Keys end up inside the APK.** Anyone who gets the APK can pull them out. Use free-tier keys only. In Google Cloud > APIs & Services > Credentials, restrict the Gemini and Safe Browsing keys: **API restrictions** to the one API each key needs, and **Application restrictions > Android apps** with package `my.kantoi.kantoi` and your signing certificate's SHA-1.

## 3. Build

From the project folder (the one with `README.md`):

```powershell
powershell -ExecutionPolicy Bypass -File .\build-windows.ps1
```

The script:
1. Checks your Flutter version.
2. Runs `flutter pub get`, `flutter analyze` and `flutter test` (about 300 tests).
3. Builds the release APK with the same settings as CI.
4. Copies the result to **`Kantoi-android.apk`** in the project folder.

It stops at the first step that fails and tells you which one.

Options:
- `-SkipTests` skips analyze and tests (faster, but you won't know if something broke).
- `-Install` installs the APK on a phone plugged in by USB. Turn on **USB debugging** in the phone's Developer options first, and add `%LOCALAPPDATA%\Android\Sdk\platform-tools` to Path so `adb` is found.

The first build downloads Gradle and the Android libraries and can take 10–20 minutes. Later builds take a few minutes.

## 4. Install on the phone

Copy `Kantoi-android.apk` to the phone (USB, Google Drive or WhatsApp to yourself), or use `-Install`. Then follow **Install on Android** in the README.

**Signing:** a local build is signed with your PC's debug key unless `app\android\key.properties` exists (see **Release signing** in the README). Android won't install it over the GitHub release, which is signed with a different key. Uninstall the old Kantoi first; its on-phone data is lost.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| `flutter` is not recognised | Path isn't set, or the PowerShell window was opened before you set it. Open a new window. |
| "Building with plugins requires symlink support" | Turn on Developer Mode (step 1.1). |
| Android licences not accepted / cmdline-tools missing | Install **Android SDK Command-line Tools** (step 1.2), then run `flutter doctor --android-licenses`. |
| `flutter analyze` or `flutter test` fails | Read the first error; it names the file and line. Fix it, or send it to Claude. |
| Gradle download or "Could not resolve" errors | Check your internet connection or proxy, then run the script again. Downloads resume. |
| Build is very slow or runs out of memory | Close Android Studio and the emulator while building. |
