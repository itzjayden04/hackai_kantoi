import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'outbox.dart';

/// Report ids (`rep-<millis>`) can repeat across phones, so the owner's uid
/// comes first.
String cloudDocId(String uid, String id) => '${uid}_$id';

/// The stored document: the masked payload exactly as built, its owner, and
/// a flat list of the one-way identifier codes so Firestore can count
/// "reports that mention this number".
Map<String, dynamic> cloudDoc(String uid, Map<String, dynamic> data) => {
      ...data,
      'uid': uid,
      'idCodes': [
        for (final i in (data['identifiers'] as List?) ?? const [])
          if (i is Map && i['code'] is String) i['code'] as String
      ],
    };

/// Sends outbox items to Firestore ('reports' and 'detections'). Throws when
/// nobody is signed in or the write fails, so the item stays queued.
class FirestoreSink implements CloudSink {
  /// Firestore only answers a write once the server has it, so offline it
  /// would wait forever. Give up and let the outbox retry.
  static const timeout = Duration(seconds: 15);

  final FirebaseFirestore? _db;
  final FirebaseAuth? _auth;
  FirestoreSink({this._db, this._auth});

  FirebaseFirestore get db => _db ?? FirebaseFirestore.instance;
  FirebaseAuth get auth => _auth ?? FirebaseAuth.instance;

  @override
  Future<void> write(String collection, String id, Map<String, dynamic> data) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) throw StateError('Not signed in');
    final ref = db.collection(collection).doc(cloudDocId(uid, id));
    try {
      await ref.set({...cloudDoc(uid, data), 'at': FieldValue.serverTimestamp()}).timeout(timeout);
    } on FirebaseException catch (e) {
      // Records are append-only, so writing one that already arrived (e.g.
      // after a timed-out first try) is refused. It is shared already.
      if (e.code != 'permission-denied') rethrow;
      if (!(await ref.get().timeout(timeout)).exists) rethrow;
    }
  }
}
