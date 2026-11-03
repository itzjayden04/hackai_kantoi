import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase project settings, passed at build time like the other keys (the
/// FIREBASE_* GitHub secrets, copied from the Android app's
/// google-services.json). Nothing is committed, and a build without them
/// stays fully on the phone.
const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
const _appId = String.fromEnvironment('FIREBASE_APP_ID');
const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
const _senderId = String.fromEnvironment('FIREBASE_SENDER_ID');

bool get firebaseConfigured => _apiKey.isNotEmpty && _appId.isNotEmpty && _projectId.isNotEmpty && _senderId.isNotEmpty;

/// Starts Firebase. False when this build has no settings or start-up
/// failed; the app then keeps its local accounts and outbox.
Future<bool> startFirebase() async {
  if (!firebaseConfigured) return false;
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
          options: const FirebaseOptions(apiKey: _apiKey, appId: _appId, messagingSenderId: _senderId, projectId: _projectId));
    }
    return true;
  } catch (e) {
    debugPrint('Kantoi: Firebase did not start: $e');
    return false;
  }
}
