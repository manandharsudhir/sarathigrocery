/// Credentials + session, independent of who stores the business data.
///
/// Users log in with phone + password. Every account has a stable id (the
/// `AppUser` document id); the profile/role lives in `UserRepository`.
/// Password recovery is by SMS OTP to a phone the user verified earlier.
/// Swap the implementation to move off Firebase Auth — each method maps to
/// one endpoint on a custom backend.
abstract class AuthRepository {
  /// Account id of the signed-in session (persisted across launches), if any.
  String? get currentAccountId;

  /// Account id, or null for wrong/unknown credentials. Throws
  /// [AuthException] for anything else (network, rate limit, ...).
  Future<String?> signIn(String phone, String password);

  /// New account's id, or null if [phone] is taken. Doesn't change the
  /// current session, so an owner can add staff while staying signed in.
  Future<String?> createAccount(String phone, String password);

  Future<void> signOut();

  Future<void> changePassword(String currentPassword, String newPassword);

  /// Re-checks the signed-in user's password before a dangerous action.
  Future<bool> verifyPassword(String password);

  /// Whether the signed-in account has proven ownership of its phone —
  /// required before OTP password reset can work for it.
  bool get phoneVerified;

  /// Sends an OTP to [phone] (the signed-in account's own number); returns a
  /// verification id for [completePhoneVerification].
  Future<String> startPhoneVerification(String phone);

  Future<void> completePhoneVerification(String verificationId, String code);

  /// Signed-out flow: sends an OTP to [phone]; returns a verification id.
  Future<String> startPasswordReset(String phone);

  /// Sets [newPassword] if [code] is right and [phone] belongs to an account
  /// that verified it. Leaves the user signed out.
  Future<void> completePasswordReset(String verificationId, String code, String newPassword);
}

/// A failure with a user-presentable [message].
class AuthException implements Exception {
  AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Minimum password rule, applied everywhere a password is set. Null = ok.
String? passwordProblem(String password) =>
    password.length < 8 ? 'Password must be at least 8 characters.' : null;

/// In-process [AuthRepository] for tests / backend-less runs. OTPs aren't
/// sent anywhere; the last one is exposed as [lastOtp]. [forDevice] gives
/// another device's view: same accounts, its own signed-in session.
class InMemoryAuthRepository implements AuthRepository {
  InMemoryAuthRepository() : _shared = _SharedAuthState();

  InMemoryAuthRepository._(this._shared);

  final _SharedAuthState _shared;
  String? _currentPhone;

  InMemoryAuthRepository forDevice() => InMemoryAuthRepository._(_shared);

  Map<String, ({String id, String password})> get _accounts => _shared.accounts;

  String? get lastOtp => _shared.lastOtp;

  @override
  String? get currentAccountId => _accounts[_currentPhone]?.id;

  @override
  Future<String?> signIn(String phone, String password) async {
    final account = _accounts[phone];
    if (account == null || account.password != password) return null;
    _currentPhone = phone;
    return account.id;
  }

  @override
  Future<String?> createAccount(String phone, String password) async {
    if (_accounts.containsKey(phone)) return null;
    final id = 'uid${_shared.nextId++}';
    _accounts[phone] = (id: id, password: password);
    return id;
  }

  @override
  Future<void> signOut() async => _currentPhone = null;

  @override
  Future<void> changePassword(String currentPassword, String newPassword) async {
    final account = _accounts[_currentPhone];
    if (account == null || account.password != currentPassword) throw AuthException('Current password is incorrect.');
    _accounts[_currentPhone!] = (id: account.id, password: newPassword);
  }

  @override
  Future<bool> verifyPassword(String password) async => _accounts[_currentPhone]?.password == password;

  @override
  bool get phoneVerified => _shared.verifiedPhones.contains(_currentPhone);

  String _sendOtp(String phone) {
    final n = _shared.nextId++;
    final id = 'v$n';
    _shared.lastOtp = '${100000 + n}';
    _shared.otps[id] = (phone: phone, code: _shared.lastOtp!);
    return id;
  }

  String _checkOtp(String verificationId, String code) {
    final otp = _shared.otps.remove(verificationId);
    if (otp == null || otp.code != code) throw AuthException('Incorrect or expired code.');
    return otp.phone;
  }

  @override
  Future<String> startPhoneVerification(String phone) async => _sendOtp(phone);

  @override
  Future<void> completePhoneVerification(String verificationId, String code) async {
    final phone = _checkOtp(verificationId, code);
    if (phone != _currentPhone) throw AuthException('That code was for a different number.');
    _shared.verifiedPhones.add(phone);
  }

  @override
  Future<String> startPasswordReset(String phone) async => _sendOtp(phone);

  @override
  Future<void> completePasswordReset(String verificationId, String code, String newPassword) async {
    final phone = _checkOtp(verificationId, code);
    final account = _accounts[phone];
    if (account == null || !_shared.verifiedPhones.contains(phone)) throw AuthException(kUnverifiedResetMessage);
    _accounts[phone] = (id: account.id, password: newPassword);
  }
}

class _SharedAuthState {
  final Map<String, ({String id, String password})> accounts = {};
  final Set<String> verifiedPhones = {};
  final Map<String, ({String phone, String code})> otps = {};
  int nextId = 1;
  String? lastOtp;
}

const kUnverifiedResetMessage =
    'No verified account for this number. OTP reset only works once you have verified your phone under Account — contact the business owner for help.';
