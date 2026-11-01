# Prompt for Faris's Claude: connect Kantoi to Firebase

> Paste everything below into Claude Code (or Claude) on Faris's machine, inside a clone of `itzjayden04/hackai_kantoi`.

---

You're helping **Faris** (GitHub `Hyeor`) add a Firebase backend to **Kantoi**. Kantoi is a Flutter Android anti-scam app for the HackAI 2026 hackathon, Track 3 "Scam Defence & Awareness". The repo owner is Jayden (GitHub `itzjayden04`). Faris already owns a Firebase project, and this work goes into the **next release tag after v1.2.0**.

## 1. What already exists (read these first)

v1.2.0 was built so that Firebase plugs in at **two backend interfaces only**, with **no screen changes**. Everything works today without Firebase: accounts are stored on the phone, and masked records wait in a local outbox.

| Plug point | File | Today's implementation | Your job |
|---|---|---|---|
| `AuthBackend` | `app/lib/auth/auth_service.dart` | `LocalAuthBackend` keeps accounts on the phone, with PBKDF2 password hashes | Add `FirebaseAuthBackend` |
| `CloudSink` | `app/lib/cloud/outbox.dart` | `Outbox.sink` is `null`, so items wait in SharedPreferences | Add `FirestoreSink` |
| Startup | `app/lib/main.dart` (around `await auth.load()`) | Loads local stores | Initialise Firebase and swap in the two classes above |

Read these files before you write any code:
- `app/lib/auth/auth_service.dart`: the `AuthBackend` interface, `AuthService`, and the `AuthProblem` messages the UI shows.
- `app/lib/auth/account.dart`: `KantoiUser`, `Registration`, `validateRegistration`, `consentVersion`.
- `app/lib/auth/otp_client.dart` and `server/otp/Code.gs`: the 6-digit email code. It is a free Google Apps Script that sends mail as kantoi.noreply@gmail.com. A successful `verify` returns `proof = base64url(HMAC-SHA256(email + "|" + exp, PROOF_KEY))`.
- `app/lib/cloud/outbox.dart`, `app/lib/cloud/detection.dart`, `app/lib/report/report_store.dart` and `ScamReport.sharedPayload()` in `app/lib/report/scam_report.dart`: these build exactly what may leave the phone.
- `app/lib/ui/auth/auth_flow.dart`: the login, register, code and forgot-password screens. Change it only where section 4.4 says to.

The UI already expects these error strings from `AuthProblem`, so reuse them:
- `"This email is already registered. Log in instead?"` (`field: 'email'`)
- `"That username is taken."` (`field: 'username'`)
- `"That username or password isn't right."`
- `"Please verify your email first."`

## 2. Hard rules (the owner's, non-negotiable)

1. **No money.** Use the **Spark (free) plan only**. No Blaze, no Cloud Functions, no paid extensions. If a feature needs Blaze, stop and say so.
2. **Privacy.** Only the masked payloads that `sharedPayload()` and `detectionPayload()` already build go to Firestore. Never upload message text, names, phone numbers in clear, screenshots, transaction numbers or safe words. The **safe word vault never goes to the cloud**.
3. **No secrets in git.** API keys, `google-services.json` and keystores go into GitHub Actions secrets and are written to disk during CI (see section 6). Add `google-services.json` to `.gitignore`.
4. **The app must still work without Firebase.** If `Firebase.initializeApp()` fails or the config is missing, keep `LocalAuthBackend` and a `null` sink. Never crash at startup.
5. **Keep CI green.** `flutter analyze` must report no issues, and all of the about 310 tests in `flutter test` must pass. Tests cannot start Firebase, so nothing Firebase-related may run when the app is not started through `main()`. Inject the backends instead.
6. **Git etiquette.**
   - Commit as Faris, using his own GitHub email.
   - **Do not add AI co-author trailers or AI session links to commits or PRs** (the owner's rule).
   - Branch from the latest `main` after PR #2 (v1.2.0) is merged, then open a PR.
   - **Jayden and Faris never push at the same time.** Tell Jayden before you push.
7. Users are total beginners. Error messages must be plain English with no Firebase jargon. For example, `"Wrong email or password."`, not `auth/invalid-credential`.

## 3. Firebase console setup (Faris does this by hand)

1. **Project settings → Add app → Android.**
   - Package name: `my.kantoi.kantoi`.
   - Add the **release signing SHA-1**: `A8:C1:23:5C:3D:1B:30:59:5E:E4:3C:E0:F6:24:D8:5A:75:F4:42:63`. This is the permanent key CI signs with, alias `kantoi`. Ask Jayden for the SHA-256 if Firebase asks for it.
   - If Faris also runs debug builds locally, add his debug SHA-1 (from `cd app/android && ./gradlew signingReport`).
   - Download `google-services.json`. **Don't commit it.**
2. **Authentication → Sign-in method:** enable **Email/Password** and **Google**. Leave "Email enumeration protection" on.
3. **Google sign-in client IDs.** The app passes `GOOGLE_SERVER_CLIENT_ID` (a GitHub secret) to `GoogleSignIn.initialize(serverClientId: …)`. For Firebase to accept the Google ID token, that ID **must be the Web client in the same Google Cloud project as Firebase**: "Web client (auto created by Google Service)" under Google Cloud → APIs & Services → Credentials. Jayden's current secret points at his own GCP project, so **Jayden must replace the `GOOGLE_SERVER_CLIENT_ID` secret with the Firebase project's Web client ID**. Tell him in the PR.
4. **Firestore Database → Create** in production mode, region `asia-southeast1` (Singapore), then paste the rules from section 5.
5. Spark limits to keep in mind: 50k reads, 20k writes and 20k deletes per day, and 1 GiB of storage. That is plenty for a demo.

## 4. Code to write

Add the packages with `flutter pub add firebase_core firebase_auth cloud_firestore`, from `app/`. Let pub choose versions that work with Flutter 3.47.7. The app's `minSdk` is already 24.

Android Gradle setup:
- Add the `com.google.gms.google-services` plugin in `app/android/settings.gradle.kts` (plugins block, `apply false`).
- Apply it in `app/android/app/build.gradle.kts`.
- The build expects `app/android/app/google-services.json`. Locally Faris drops it in; CI writes it from a secret (section 6).
- Wrap the plugin so a build **without** the file still succeeds. For example, apply the plugin only `if (file("google-services.json").exists())`. This keeps forks and Jayden's local builds working.

### 4.1 `app/lib/cloud/firestore_sink.dart`

```dart
class FirestoreSink implements CloudSink {
  // write(collection, id, data):
  //   - collection is 'reports' or 'detections' (the only two used)
  //   - doc id = '${uid}_$id' (report ids are 'rep-<millis>', so they can collide across phones)
  //   - set({...data, 'uid': uid, 'at': FieldValue.serverTimestamp(),
  //          'idCodes': [for (i in data['identifiers'] ?? []) i['code']]})
  //   - throw when there is no signed-in Firebase user or the write fails,
  //     so Outbox keeps the item and retries later (that is the contract).
}
```

`idCodes` is a flat array of the one-way identifier hashes. Firestore can then answer "how many reports mention this number" with `where('idCodes', arrayContains: code).count()`. That query is optional extra work (section 7).

Don't add or change payload fields. `sharedPayload()` and `detectionPayload()` are the privacy boundary, and `test/report_cloud_test.dart` checks them.

### 4.2 `app/lib/auth/firebase_auth_backend.dart`

Implement every method of `AuthBackend`:

- **`register(r, proof:)`**
  - If `proof` is empty, throw `AuthProblem('Please verify your email first.')`. Proof is `'unverified'` only in builds without the email-code secrets.
  - Call `createUserWithEmailAndPassword(email, password)` and `updateDisplayName(fullName)`.
  - In a Firestore **transaction**, create `usernames/{usernameLower}` = `{uid, email}`. If it already exists, delete the new auth user and throw `AuthProblem('That username is taken.', field: 'username')`.
  - Write `users/{uid}` = `{fullName, username, phone, method: 'email', created, consent: consentVersion, consentAt}`.
  - Map `email-already-in-use` to the "already registered" problem.
  - Return a `KantoiUser` whose `uid` is the Firebase uid.
- **`signInPassword(id, password)`**
  - If `id` has no `@`, `get()` `usernames/{idLower}` to find the email. A missing doc gives the same "isn't right" message, so you don't reveal which usernames exist.
  - Then call `signInWithEmailAndPassword`.
  - Build `KantoiUser` from `users/{uid}`.
- **`signInGoogle(...)`** needs Google's **ID token**. Today `AuthService.signInGoogle()` gets `a = await GoogleSignIn.instance.authenticate()` and passes only `id/email/name`.
  - Add an optional `String? idToken` parameter to the interface method and to `LocalAuthBackend`, which ignores it.
  - Pass `a.authentication.idToken` in.
  - In the Firebase backend, call `signInWithCredential(GoogleAuthProvider.credential(idToken: idToken))`.
  - Create `users/{uid}` on first sign-in with `method: 'google'` and `consent: consentVersion`. Google users tick the PDPA box in a dialog before sign-in (`_ConsentDialog` in `auth_flow.dart`). Keep it.
- **`deleteAccount(u)`**
  - Delete the user's `reports` and `detections` docs (`where('uid', isEqualTo: uid)`), then `usernames/{username}` and `users/{uid}`, then `currentUser.delete()`.
  - On `requires-recent-login`, throw an `AuthProblem` asking the user to log out, log in again and retry.
  - This is the PDPA "delete my data" path. Today `PrivacyControls._deleteAll` ("Delete all my Kantoi data" in Settings) only calls `localStore.deleteAll()`. When the backend is Firebase, also call `auth.deleteAccount()` and update the dialog text to say the account and shared records are deleted too.
- **`hasPasswordAccount(email)`**: with enumeration protection on, `fetchSignInMethodsForEmail` returns nothing useful. Choose one:
  - (a) Always return `true` and let the reset step answer generically ("If an account uses this email, we sent a link").
  - (b) Store a `emailIndex/{sha256(email)}` doc on register.
  - Recommend **(a)**.
- **`resetPassword(email, password, proof:)`**: a client can't set a password for a user who isn't signed in, and Spark has no Functions. Use Firebase's own **`sendPasswordResetEmail(email)`** instead (see 4.4). Have this method throw `UnsupportedError`, or remove it from the Firebase path.
- **Sign out:** add `Future<void> signOut()` to `AuthBackend` (a no-op locally, `FirebaseAuth.instance.signOut()` for Firebase). Call it from `AuthService.signOut()`.

Keep `AuthService` behaviour the same:
- 7-day inactivity logout for **email** accounts.
- The user cached in SharedPreferences, so the app opens offline.
- Phone protection keeps running when the user is logged out.

On startup, if `FirebaseAuth.instance.currentUser` is null but the cached user is a Firebase user, treat it as logged out.

### 4.3 `app/lib/main.dart`

```dart
// before auth.load():
try {
  await Firebase.initializeApp();          // reads google-services.json on Android
  auth.backend = FirebaseAuthBackend();
  cloudOutbox.sink = FirestoreSink();
} catch (_) {
  // no config in this build: stay fully local (rule 4)
}
// after loading stores:
unawaited(cloudOutbox.flush());           // send anything queued while offline
```

Also call `cloudOutbox.flush()` on `AppLifecycleState.resumed` (there's already a lifecycle hook in `KantoiApp`) and right after a successful sign-in.

### 4.4 Forgot password: the one small UI change

`_Forgot` in `auth_flow.dart` currently goes email → 6-digit code → new password. For Firebase accounts:
- Add `bool get resetsByLink` to `AuthBackend` (false locally, true for Firebase).
- When it is true, the Forgot screen sends `FirebaseAuth.instance.sendPasswordResetEmail(email: e)` and shows: "Check your email. We sent a link to reset your password. After you set it, come back and log in."
- Keep the existing styling: `_TopBar`, `_Hero`, `_Field`, navy `FilledButton`.

Registration keeps the Apps Script 6-digit code. It already works, it's free, and it's the demo flow.

Known limit: Spark has no server code, so the HMAC `proof` can't be re-checked by Firebase. The code check happens in the app plus Apps Script. That's acceptable for the hackathon, and you should note it in the PR.

## 5. Firestore security rules

```
rules_version = '2';
service cloud.firestore {
  match /databases/{db}/documents {
    function signedIn() { return request.auth != null; }
    function mine(d) { return signedIn() && d.uid == request.auth.uid; }

    match /users/{uid} {
      allow read, create, update: if signedIn() && request.auth.uid == uid;
      allow delete: if signedIn() && request.auth.uid == uid;
    }

    // username -> {uid, email}; get only (no listing), so names can't be dumped
    match /usernames/{name} {
      allow get: if true;
      allow create: if signedIn() && request.resource.data.uid == request.auth.uid
                    && request.resource.data.keys().hasOnly(['uid', 'email']);
      allow delete: if signedIn() && resource.data.uid == request.auth.uid;
      allow list, update: if false;
    }

    // masked, append-only community data
    match /reports/{id} {
      allow create: if mine(request.resource.data)
        && request.resource.data.keys().hasOnly(['v','kind','group','channel','identifiers','domains',
             'impersonated','lostMoney','amountMinor','currency','payment','incidentDay',
             'reportedOfficially','appVersion','uid','at','idCodes'])
        && request.resource.data.identifiers.size() <= 20
        && request.resource.data.domains.size() <= 20;
      allow read: if signedIn();          // masked data only; enables "reported N times"
      allow delete: if signedIn() && resource.data.uid == request.auth.uid;
      allow update: if false;
    }

    match /detections/{id} {
      allow create: if mine(request.resource.data)
        && request.resource.data.keys().hasOnly(['v','kind','level','score','confidence','cues','app',
             'source','hour','domains','identifiers','appVersion','uid','at','idCodes'])
        && request.resource.data.identifiers.size() <= 20;
      allow read: if signedIn();
      allow delete: if signedIn() && resource.data.uid == request.auth.uid;
      allow update: if false;
    }
  }
}
```

Check the key lists against the real payload maps in `scam_report.dart` and `detection.dart` before you deploy. A missing key makes every write fail silently, and items will just sit in the outbox.

## 6. CI (`.github/workflows/build.yml`)

- New secret **`GOOGLE_SERVICES_JSON_BASE64`**: Faris or Jayden adds it, made with `base64 -w0 google-services.json`.
- In the `android` job, before `flutter build apk`, add a step:
  ```yaml
  - name: Firebase config
    env:
      GOOGLE_SERVICES_JSON_BASE64: ${{ secrets.GOOGLE_SERVICES_JSON_BASE64 }}
    run: |
      if [ -z "$GOOGLE_SERVICES_JSON_BASE64" ]; then echo "No Firebase config: app stays local"; exit 0; fi
      echo "$GOOGLE_SERVICES_JSON_BASE64" | base64 -d > android/app/google-services.json
  ```
- Don't touch the existing secrets or the signing step:
  - `GEMINI_API_KEY`
  - `KANTOI_1` (maps to `GEMINI_API_KEY_2`)
  - `OTP_URL`, `OTP_APP_KEY`
  - `GOOGLE_SERVER_CLIENT_ID`
  - `ANDROID_KEYSTORE_*`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`
- The `test` job must not need Firebase.

## 7. Optional (only if the core is done and green)

- **"Reported N times on Kantoi":** the Report-done screen (`_done` in `app/lib/ui/report/report_tab.dart`) currently counts this phone's own reports. With Firestore you can count across everyone: `collection('reports').where('idCodes', arrayContains: code).count().get()`. Put the call behind a small interface so tests can fake it, and fall back to the local count when offline.
- **Withdraw after sending:** when a user marks a shared detection "not a scam", `Outbox.withdraw` only drops queued items. You could add `delete(collection, id)` to `CloudSink` and call it for docs that were already sent.

## 8. Tests to add

- Fake-backed unit tests for the pure parts:
  - Firebase error code to `AuthProblem` message mapping.
  - The doc-id and `idCodes` building in `FirestoreSink`. Factor it into a pure function.
- Make sure `test/auth_test.dart`, `test/report_cloud_test.dart` and the widget tests still pass unchanged, since they use the local backends.
- Manual test on a real phone with the CI APK (the `Kantoi-android` artifact):
  1. Register by email with the code.
  2. Log out, then log in with the username.
  3. Use Forgot password and follow the link.
  4. Sign in with Google.
  5. Submit a report and see the doc appear in the Firestore console with no clear-text personal data.
  6. Delete the account and see the user's docs disappear.

## 9. Done means

- [ ] Email register, login (by email or username), logout and the 7-day logout all work against Firebase Auth.
- [ ] Google sign-in works on the release APK, after Jayden updates `GOOGLE_SERVER_CLIENT_ID` to the Firebase Web client.
- [ ] Reports and high-confidence detections reach Firestore masked. The outbox empties when the phone is online.
- [ ] Deleting the account removes the Auth user and the user's Firestore docs.
- [ ] The app still runs fully with no Firebase config (fork, offline, or missing secret).
- [ ] `flutter analyze` is clean, `flutter test` is green, and the CI APK builds.
- [ ] The PR lists the secrets Jayden must add or change (`GOOGLE_SERVICES_JSON_BASE64`, `GOOGLE_SERVER_CLIENT_ID`), the Firestore rules Faris deployed, and the HMAC-proof limit.
