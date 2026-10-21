# Run Kantoi on a Windows PC

**Yes, Kantoi runs in the free Android Emulator that comes with Android Studio.** Use it for testing and as a backup during the pitch. For the live demo, a real phone shown on the screen (Option B) is still the most convincing, because WhatsApp and real calls only work on a real phone.

> Windows Subsystem for Android was shut down by Microsoft in March 2025, so don't use it. BlueStacks and similar "game players" can install the APK, but they hide Android's Accessibility and notification-access settings, so phone protection won't work there.

---

## Option A: Android Emulator (Android Studio)

### What you need
- Windows 10 or 11, 64-bit, with **16 GB RAM** (8 GB works but is slow) and about **15 GB** free disk space.
- **Virtualization turned on.** Open Task Manager > Performance > CPU and check that "Virtualization: Enabled". If it says Disabled, turn on Intel VT-x / AMD SVM in the BIOS.
- The APK: https://github.com/itzjayden04/hackai_kantoi/releases/latest/download/Kantoi-android.apk

### 1. Install Android Studio (one time, about 15 minutes)
1. Download Android Studio from **https://developer.android.com/studio** and run the installer. Keep the default options, including **Android Virtual Device**.
2. Open Android Studio and finish the **Setup Wizard** with **Standard**. It downloads the Android SDK and the emulator.
3. If Windows asks to turn on **Windows Hypervisor Platform**, allow it and restart.
   You can also turn it on yourself: Start > "Turn Windows features on or off" > tick **Windows Hypervisor Platform** > OK > restart.

### 2. Create a virtual phone
1. On the Android Studio welcome screen, click **More Actions > Virtual Device Manager**. Inside a project, use **Tools > Device Manager**.
2. Click **+ (Create Virtual Device)**, choose **Pixel 7** (any phone works), then **Next**.
3. Choose the system image **API 34 (Android 14), x86_64, "Google APIs"**. Click the download arrow next to it, wait, then **Next**.
   - Pick **Google APIs**, not **Google Play**. The Play image has Play Protect, which may block Kantoi.
4. Name it "Kantoi test", click **Finish**, then press **▶ (Play)** to start it. The first boot takes 1–3 minutes.

### 3. Install Kantoi
1. Download `Kantoi-android.apk` on your PC.
2. **Drag the APK file onto the emulator window.** It installs by itself, and Kantoi appears in the app list (swipe up on the home screen).

### 4. Allow restricted settings (Android 13 and newer)
1. Open Kantoi and follow setup.
2. At the **Accessibility** step, if Android says **"Restricted setting"**:
   1. Go to **Settings > Apps > Kantoi**.
   2. Tap **⋮** (top right) > **Allow restricted settings**.
   3. Confirm, then go back to Kantoi and finish setup.
3. Allow every card: notifications, notification access, display over other apps, Accessibility, caller ID & spam app, photos, battery.
4. The top bar should show the green **Protected** pill.

### 5. Simulate scams on the emulator (no real SIM needed)
Click **⋯ (Extended controls)** on the emulator's side toolbar, then **Phone**:
- **Scam SMS:** in **From**, type a number such as `+60123456789`. Paste a scam text into the message box, for example: *"POS MALAYSIA: Your parcel is held due to an unpaid fee of RM2.50. Pay within 24 hours: https://poslaju-my-redelivery.top/pay"*. Click **Send message**. Kantoi's notification or pause card should appear.
- **Friend asking for money:** send *"Bro can transfer me RM500 now? urgent, phone rosak guna nombor baru"* the same way.
- **Risky call:** type a number and click **Call device**. To test the block, first mark that number in Kantoi, then call again.
- **Scam website:** open Chrome in the emulator and type a test scam or gambling address. Kantoi should close the page.
- **Check tab and Trace:** these work exactly as on a phone (paste, samples, Trace map).

**Not possible in the emulator:** WhatsApp and Telegram (they need a real phone number) and real phone calls. Test those on your phone.

### Tips
- **Slow or black screen:** in Device Manager, click **✎ (Edit)** on the device > **Show Advanced Settings** > set **Graphics: Hardware** and **RAM: 4096 MB**.
- **Copy and paste from your PC** works inside the emulator.
- **Screenshot:** the camera icon on the side toolbar, useful for the pitch deck placeholders.
- **Installing a newer APK:** drag the new APK onto the emulator again. It updates in place and keeps your permissions.

---

## Option B: Show your real phone on the laptop screen (best for the live pitch)
Use **scrcpy**: free, open source, no app installed on the phone.
1. On the phone, turn on **Developer options**. Go to **Settings > About phone** and tap **Build number** 7 times. On Honor: Settings > About phone > **Build number**.
2. In **Settings > System > Developer options**, turn on **USB debugging**.
3. On the PC, download scrcpy for Windows from **https://github.com/Genymobile/scrcpy/releases** (the `scrcpy-win64-…zip`) and unzip it.
4. Connect the phone with a USB cable. On the phone, tap **Allow USB debugging** and tick **Always allow**.
5. Double-click **scrcpy.exe**. The phone screen appears in a window on the laptop, so you can project it and control it with the mouse.

This shows the real thing to the judges: WhatsApp messages from a teammate, the chat badge, notifications, the pause card and calls. Keep the emulator open as a backup in case the phone or cable fails.
