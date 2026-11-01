/// Wires accounts and community reports into the app at start-up.
library;

import '../engine/community/community.dart';
import '../engine/relationship.dart' show linkedReportCounter;
import 'auth_service.dart';
import 'firebase_backend.dart';
import 'firebase_setup.dart';

export 'auth_service.dart';
export 'firebase_setup.dart' show firebaseConfigured, firebaseReady, firebaseProblem;

/// Starts Firebase (when configured), the account service and the
/// community store. Safe to call when Firebase is not configured.
Future<void> startAccounts() async {
  await initFirebase();
  if (!firebaseReady) {
    await auth.start();
    return;
  }
  auth = AuthService(FirebaseAuthBackend(), onSignedIn: (u, {required isNew}) => saveProfile(u, isNew: isNew));
  await auth.start();
  final store = FirestoreCommunity(auth);
  communityIntel = store;
  // The relationship check's "already reported by others" lookup.
  linkedReportCounter = (ids) async {
    final found = indicatorsFromIdentifiers(ids);
    if (found.isEmpty || !auth.signedIn) return 0;
    return communityScamReporters(await store.lookup(found));
  };
}

/// Whether the sign-in screen should show before the app.
bool get needsSignIn => auth.available && !auth.signedIn && !auth.guest.value;
