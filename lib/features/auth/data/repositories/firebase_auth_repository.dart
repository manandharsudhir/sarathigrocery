import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'package:sarathigrocery/features/auth/domain/repositories/auth_repository.dart';

/// Firebase Auth behind [AuthRepository].
///
/// Phone + password login: each phone maps to a synthetic email/password
/// account. Password recovery links a Firebase *phone* credential to that
/// same account (the one-time "verify your phone" step); a later OTP
/// sign-in then lands in the same account, which may set a new password.
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository([FirebaseAuth? auth]) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  static const _emailDomain = 'sarathigrocery.app';

  /// Stored phones are local 10-digit numbers; SMS needs E.164.
  static const _countryCode = '+977';

  static String _email(String phone) => '$phone@$_emailDomain';

  static String _e164(String phone) => phone.startsWith('+') ? phone : '$_countryCode$phone';

  static const _badCredentials = {'invalid-credential', 'user-not-found', 'wrong-password', 'invalid-email', 'user-disabled'};

  static AuthException _wrap(FirebaseAuthException e) => AuthException(switch (e.code) {
        'too-many-requests' => 'Too many attempts. Try again later.',
        'network-request-failed' => 'No internet connection.',
        'invalid-verification-code' || 'invalid-verification-id' || 'session-expired' => 'Incorrect or expired code.',
        'invalid-phone-number' => 'That phone number is not valid.',
        'weak-password' => 'Password is too weak.',
        'requires-recent-login' => 'Please log out and log in again, then retry.',
        _ => e.message ?? e.code,
      });

  @override
  String? get currentAccountId => _auth.currentUser?.uid;

  @override
  Future<String?> signIn(String phone, String password) async {
    try {
      final result = await _auth.signInWithEmailAndPassword(email: _email(phone), password: password);
      return result.user!.uid;
    } on FirebaseAuthException catch (e) {
      if (_badCredentials.contains(e.code)) return null;
      throw _wrap(e);
    }
  }

  @override
  Future<String?> createAccount(String phone, String password) async {
    // createUser* signs the new user in on whichever app it runs on, so use a
    // throwaway secondary app to keep the current (owner's) session intact.
    final app = await Firebase.initializeApp(name: 'account-creation-${DateTime.now().microsecondsSinceEpoch}', options: Firebase.app().options);
    try {
      final result = await FirebaseAuth.instanceFor(app: app).createUserWithEmailAndPassword(email: _email(phone), password: password);
      return result.user!.uid;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') return null;
      throw _wrap(e);
    } finally {
      await app.delete();
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
  bool get phoneVerified => _auth.currentUser?.phoneNumber != null;

  // ---- OTP plumbing. Mobile uses verifyPhoneNumber (verification id +
  // code → credential); web can only use reCAPTCHA-backed
  // ConfirmationResults, kept here by a local id.

  final Map<String, ConfirmationResult> _webConfirmations = {};
  final Map<String, PhoneAuthCredential> _autoRetrieved = {};

  Future<String> _sendCode(String phone) async {
    final completer = Completer<String>();
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: _e164(phone),
        // Android may verify instantly (no SMS typed); remember the
        // credential under a synthetic id so the rest of the flow is uniform.
        verificationCompleted: (credential) {
          if (completer.isCompleted) return;
          final id = 'auto-${DateTime.now().microsecondsSinceEpoch}';
          _autoRetrieved[id] = credential;
          completer.complete(id);
        },
        verificationFailed: (e) {
          if (!completer.isCompleted) completer.completeError(_wrap(e));
        },
        codeSent: (verificationId, _) {
          if (!completer.isCompleted) completer.complete(verificationId);
        },
        codeAutoRetrievalTimeout: (_) {},
      );
    } on FirebaseAuthException catch (e) {
      throw _wrap(e);
    }
    return completer.future;
  }

  PhoneAuthCredential _credential(String verificationId, String code) =>
      _autoRetrieved.remove(verificationId) ?? PhoneAuthProvider.credential(verificationId: verificationId, smsCode: code);

  String _keepWeb(ConfirmationResult confirmation) {
    final id = 'web-${DateTime.now().microsecondsSinceEpoch}';
    _webConfirmations[id] = confirmation;
    return id;
  }

  @override
  Future<String> startPhoneVerification(String phone) async {
    if (!kIsWeb) return _sendCode(phone);
    try {
      return _keepWeb(await _auth.currentUser!.linkWithPhoneNumber(_e164(phone)));
    } on FirebaseAuthException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<void> completePhoneVerification(String verificationId, String code) async {
    try {
      final web = _webConfirmations.remove(verificationId);
      if (web != null) {
        await web.confirm(code);
      } else {
        await _auth.currentUser!.linkWithCredential(_credential(verificationId, code));
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use') throw AuthException('This number is already verified on another account.');
      if (e.code == 'provider-already-linked') return;
      throw _wrap(e);
    }
  }

  @override
  Future<String> startPasswordReset(String phone) async {
    if (!kIsWeb) return _sendCode(phone);
    try {
      return _keepWeb(await _auth.signInWithPhoneNumber(_e164(phone)));
    } on FirebaseAuthException catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<void> completePasswordReset(String verificationId, String code, String newPassword) async {
    try {
      final web = _webConfirmations.remove(verificationId);
      final result = web != null ? await web.confirm(code) : await _auth.signInWithCredential(_credential(verificationId, code));
      final user = result.user!;
      // A phone nobody linked creates a brand-new, empty phone-only account.
      // Remove it: only accounts that verified this number may be reset.
      if ((result.additionalUserInfo?.isNewUser ?? false) || user.email == null) {
        await user.delete();
        throw AuthException(kUnverifiedResetMessage);
      }
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      throw _wrap(e);
    } finally {
      await _auth.signOut();
    }
  }
}
