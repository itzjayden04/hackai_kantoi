/// Firebase start-up. The project settings come from --dart-define (put
/// them in app/secrets.json, like the other keys), so no
/// google-services.json is needed and nothing is committed. When they are
/// missing, Firebase stays off and Kantoi works exactly as before, without
/// accounts.
library;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
const _appId = String.fromEnvironment('FIREBASE_APP_ID');
const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
const _senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
const _bucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');

/// Whether this build was given Firebase settings.
bool get firebaseConfigured => _apiKey.isNotEmpty && _appId.isNotEmpty && _projectId.isNotEmpty && _senderId.isNotEmpty;

FirebaseOptions? firebaseOptions() => firebaseConfigured
    ? const FirebaseOptions(
        apiKey: _apiKey,
        appId: _appId,
        messagingSenderId: _senderId,
        projectId: _projectId,
        storageBucket: _bucket == '' ? null : _bucket,
      )
    : null;

/// True once Firebase started. False when not configured or start-up failed
/// (then accounts are hidden and the app runs on the device only).
bool firebaseReady = false;

/// Why Firebase is off, for Settings.
String firebaseProblem = '';

Future<void> initFirebase() async {
  final o = firebaseOptions();
  if (o == null) {
    firebaseProblem = 'Accounts are not set up in this build.';
    return;
  }
  try {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: o);
    firebaseReady = true;
  } catch (e) {
    firebaseProblem = 'Could not start accounts: $e';
    debugPrint('Kantoi: Firebase failed to start: $e');
  }
}
