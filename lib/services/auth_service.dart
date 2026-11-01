import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  AuthService._();
  static final instance = AuthService._();

  final _auth = FirebaseAuth.instance;

  Stream<User?> get changes => _auth.authStateChanges();

  Future<void> signIn(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email.trim(), password: password);

  Future<void> signUp(String name, String email, String password) async {
    final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(), password: password);
    await cred.user!.updateDisplayName(name.trim());
    await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).set({
      'name': name.trim(),
      'email': email.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'reminderEnabled': false,
      'reminderHour': 21,
      'reminderMinute': 0,
    }, SetOptions(merge: true));
  }

  Future<void> resetPassword(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  Future<void> signOut() => _auth.signOut();

  /// Turns Firebase error codes into messages a user can act on.
  static String friendlyError(Object e) {
    if (e is FirebaseAuthException) {
      return switch (e.code) {
        'invalid-email' => 'That email address doesn\'t look right.',
        'user-not-found' ||
        'wrong-password' ||
        'invalid-credential' =>
          'Incorrect email or password.',
        'email-already-in-use' => 'An account already exists for that email.',
        'weak-password' => 'Use at least 6 characters for your password.',
        'network-request-failed' => 'No internet connection.',
        'too-many-requests' => 'Too many attempts. Try again in a minute.',
        _ => e.message ?? 'Something went wrong.',
      };
    }
    return 'Something went wrong. Please try again.';
  }
}
