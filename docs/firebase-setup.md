# Connect Kantoi to Firebase

Kantoi uses Firebase for online accounts (Authentication) and the shared scam database (Firestore). It runs on the free **Spark** plan; no Cloud Functions or paid features are used. A build without the Firebase secrets works exactly as before: accounts stay on the phone and shared records wait in the outbox.

## 1. Firebase console (once)

1. **Project settings > Add app > Android.** Package name `my.kantoi.kantoi`. Add the release signing SHA-1 (the CI "Signing certificate" step prints it) and, for local debug builds, your debug SHA-1 (`cd app/android && ./gradlew signingReport`).
2. Download `google-services.json`, but **don't commit it** (it is in `.gitignore`). Kantoi reads its values from build secrets instead (step 3).
3. **Authentication > Sign-in method:** turn on **Email/Password** and **Google**. Leave email enumeration protection on.
4. **Firestore Database > Create database** in production mode, region `asia-southeast1`.
5. **Firestore > Rules:** paste [`firestore.rules`](../firestore.rules) and publish (or run `firebase deploy --only firestore:rules` from the repo root).

## 2. Google sign-in

Firebase only accepts a Google ID token issued for its own project. Set the `GOOGLE_SERVER_CLIENT_ID` secret to the **Web client** of the Firebase project: Google Cloud console > APIs & Services > Credentials > "Web client (auto created by Google Service)".

## 3. GitHub secrets

Copy these from `google-services.json`:

| Secret | Where in google-services.json |
| --- | --- |
| `FIREBASE_API_KEY` | `client[0].api_key[0].current_key` |
| `FIREBASE_APP_ID` | `client[0].client_info.mobilesdk_app_id` |
| `FIREBASE_PROJECT_ID` | `project_info.project_id` |
| `FIREBASE_SENDER_ID` | `project_info.project_number` |

For a local build, put the same four keys in `app/secrets.json` and run `flutter run --dart-define-from-file=secrets.json`.

## What is stored

| Collection | Contents |
| --- | --- |
| `users/{uid}` | Name, username, phone, sign-in method, consent version and dates. The email stays in Firebase Auth. |
| `usernames/{username}` | `{uid, email}`, so people can log in with their username. Readable one at a time, never listed. |
| `reports/{uid}_{id}` | `ScamReport.sharedPayload()` plus `uid`, `at`, `idCodes`. Masked only. |
| `detections/{uid}_{id}` | `detectionPayload()` plus `uid`, `at`, `idCodes`. Masked only. |

Message text, screenshots, transaction numbers and safe words never leave the phone. Reports and detections are append-only. "Delete all my Kantoi data" in Settings deletes the user's records, username, profile and account.

## How it behaves

- **Sign-up** still checks the 6-digit email code (server/otp) before the Firebase account is created. Spark has no server code, so Firebase cannot re-check the code's signed proof; the check happens in the app and the Apps Script.
- **Forgot password** emails a Firebase reset link instead of a code.
- **Phone accounts from before Firebase** are not moved over. Those users are logged out once and register again.
- **Offline:** shared records wait in the outbox and are sent on start, sign-in and when the app comes back to the front.
