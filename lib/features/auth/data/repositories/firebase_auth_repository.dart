import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:sarathigrocery/features/auth/domain/repositories/auth_repository.dart';

/// Firebase Auth behind [AuthRepository]: plain email/password accounts.
/// Verification and reset emails are Firebase's own (free on the Spark
/// plan; templates in the Firebase console).
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository([FirebaseAuth? auth]) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  static const _badCredentials = {'invalid-credential', 'user-not-found', 'wrong-password', 'invalid-email', 'user-disabled'};

  static AuthException _wrap(FirebaseAuthException e) => AuthException(switch (e.code) {
        'too-many-requests' => 'Too many attempts. Try again later.',
        'network-request-failed' => 'No internet connection.',
        'invalid-email' => 'Enter a valid email address.',
        'email-already-in-use' => kEmailTakenMessage,
        'weak-password' => 'Password is too weak.',
        'requires-recent-login' => 'Please log out and log in again, then retry.',
        _ => e.message ?? e.code,
      });

  @override
  String? get currentAccountId => _auth.currentUser?.uid;

  @override
  String? get currentEmail {
    final email = _auth.currentUser?.email;
    return email == null ? null : normalizeEmail(email);
  }

  @override
  Future<String?> signIn(String email, String password) async {
    try {
      final result = await _auth.signInWithEmailAndPassword(email: normalizeEmail(email), password: password);
      return result.user!.uid;
    } on FirebaseAuthException catch (e) {
      if (_badCredentials.contains(e.code)) return null;
      throw _wrap(e);
    }
  }

  @override
  Future<String?> createAccount(String email, String password) async {
    // createUser* signs the new user in on whichever app it runs on, so use a
    // throwaway secondary app to keep the current (owner's) session intact.
    final app = await Firebase.initializeApp(name: 'account-creation-${DateTime.now().microsecondsSinceEpoch}', options: Firebase.app().options);
    try {
      final result = await FirebaseAuth.instanceFor(app: app).createUserWithEmailAndPassword(email: normalizeEmail(email), password: password);
      return result.user!.uid;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') return null;
      throw _wrap(e);
    } finally {
      await app.delete();
    }
  }

  @override
  Future<void> signUp(String email, String password) async {
    try {
      final result = await _auth.createUserWithEmailAndPassword(email: normalizeEmail(email), password: password);
      await result.user!.sendEmailVerification();
    } on FirebaseAuthException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> changePassword(String currentPassword, String newPassword) async {
    final user = _auth.currentUser!;
    try {
      await user.reauthenticateWithCredential(EmailAuthProvider.credential(email: user.email!, password: currentPassword));
    } on FirebaseAuthException catch (e) {
      if (_badCredentials.contains(e.code)) throw AuthException('Current password is incorrect.');
      throw _wrap(e);
    }
    try {
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<bool> verifyPassword(String password) async {
    final user = _auth.currentUser;
    if (user == null) return false;
    try {
      await user.reauthenticateWithCredential(EmailAuthProvider.credential(email: user.email!, password: password));
      return true;
    } on FirebaseAuthException catch (e) {
      if (_badCredentials.contains(e.code)) return false;
      throw _wrap(e);
    }
  }

  @override
  bool get emailVerified => _auth.currentUser?.emailVerified ?? false;

  @override
  Future<void> sendEmailVerification() async {
    try {
      await _auth.currentUser!.sendEmailVerification();
    } on FirebaseAuthException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<bool> reloadEmailVerified() async {
    try {
      await _auth.currentUser!.reload();
      final user = _auth.currentUser!;
      if (user.emailVerified) await user.getIdToken(true); // rules read email_verified next
      return user.emailVerified;
    } on FirebaseAuthException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: normalizeEmail(email));
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') return;
      throw _wrap(e);
    }
  }

  @override
  Future<void> deleteAccount(String password) async {
    if (!await verifyPassword(password)) throw AuthException('Password is incorrect.');
    try {
      await _auth.currentUser!.delete();
    } on FirebaseAuthException catch (e) {
      throw _wrap(e);
    }
    await _auth.signOut();
  }
}
