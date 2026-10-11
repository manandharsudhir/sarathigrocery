/// Credentials + session, independent of who stores the business data.
///
/// Users log in with email + password. Every account has a stable id (the
/// `AppUser` document id); the profile/role lives in `UserRepository`.
/// Password recovery is a reset link emailed to that address; creating a
/// shop needs a verified email. Swap the implementation to move off
/// Firebase Auth — each method maps to one endpoint on a custom backend.
abstract class AuthRepository {
  /// Account id of the signed-in session (persisted across launches), if any.
  String? get currentAccountId;

  /// Email of the signed-in account, normalised by [normalizeEmail].
  String? get currentEmail;

  /// Account id, or null for wrong/unknown credentials. Throws
  /// [AuthException] for anything else (network, rate limit, ...).
  Future<String?> signIn(String email, String password);

  /// New account's id, or null if [email] is taken. Doesn't change the
  /// current session, so an owner can add staff while staying signed in.
  Future<String?> createAccount(String email, String password);

  /// Sign-up: creates the login, signs it in and emails a verification
  /// link. Throws [AuthException] if [email] already has a login.
  Future<void> signUp(String email, String password);

  Future<void> signOut();

  Future<void> changePassword(String currentPassword, String newPassword);

  /// Re-checks the signed-in user's password before a dangerous action.
  Future<bool> verifyPassword(String password);

  /// Whether the signed-in account has clicked its verification link (as of
  /// the last [reloadEmailVerified]).
  bool get emailVerified;

  Future<void> sendEmailVerification();

  /// Re-reads [emailVerified] from the backend (and refreshes the token the
  /// rules see). Returns the new value.
  Future<bool> reloadEmailVerified();

  /// Emails a password reset link to [email]. Silently does nothing for an
  /// unknown address (doesn't reveal which emails have logins).
  Future<void> sendPasswordReset(String email);

  /// Deletes the signed-in login for good (re-checking [password] first, as
  /// Firebase wants a recent sign-in) and signs out. Throws [AuthException].
  Future<void> deleteAccount(String password);
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

/// Emails are compared and stored trimmed + lowercased.
String normalizeEmail(String email) => email.trim().toLowerCase();

/// Null = looks like an email.
String? emailProblem(String email) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email) ? null : 'Enter a valid email address.';

/// In-process [AuthRepository] for tests / backend-less runs. No email is
/// sent: [verifyEmail] stands in for clicking the link, and
/// [resetPasswordFor] for following a reset link. [forDevice] gives another
/// device's view: same accounts, its own signed-in session.
class InMemoryAuthRepository implements AuthRepository {
  InMemoryAuthRepository() : _shared = _SharedAuthState();

  InMemoryAuthRepository._(this._shared);

  final _SharedAuthState _shared;
  String? _current;
  bool _verified = false;

  InMemoryAuthRepository forDevice() => InMemoryAuthRepository._(_shared);

  Map<String, ({String id, String password})> get _accounts => _shared.accounts;

  /// Addresses a reset link was sent to, in order.
  List<String> get sentResets => _shared.sentResets;

  void verifyEmail(String email) => _shared.verifiedEmails.add(normalizeEmail(email));

  void resetPasswordFor(String email, String newPassword) {
    final key = normalizeEmail(email);
    _accounts[key] = (id: _accounts[key]!.id, password: newPassword);
  }

  @override
  String? get currentAccountId => _accounts[_current]?.id;

  @override
  String? get currentEmail => _current;

  @override
  Future<String?> signIn(String email, String password) async {
    final key = normalizeEmail(email);
    final account = _accounts[key];
    if (account == null || account.password != password) return null;
    _current = key;
    _verified = _shared.verifiedEmails.contains(key);
    return account.id;
  }

  @override
  Future<String?> createAccount(String email, String password) async {
    final key = normalizeEmail(email);
    if (_accounts.containsKey(key)) return null;
    final id = 'uid${_shared.nextId++}';
    _accounts[key] = (id: id, password: password);
    return id;
  }

  @override
  Future<void> signUp(String email, String password) async {
    if (await createAccount(email, password) == null) throw AuthException(kEmailTakenMessage);
    await signIn(email, password);
  }

  @override
  Future<void> signOut() async => _current = null;

  @override
  Future<void> changePassword(String currentPassword, String newPassword) async {
    final account = _accounts[_current];
    if (account == null || account.password != currentPassword) throw AuthException('Current password is incorrect.');
    _accounts[_current!] = (id: account.id, password: newPassword);
  }

  @override
  Future<bool> verifyPassword(String password) async => _accounts[_current]?.password == password;

  @override
  bool get emailVerified => _current != null && _verified;

  @override
  Future<void> sendEmailVerification() async {}

  @override
  Future<bool> reloadEmailVerified() async => _verified = _shared.verifiedEmails.contains(_current);

  @override
  Future<void> sendPasswordReset(String email) async => _shared.sentResets.add(normalizeEmail(email));

  @override
  Future<void> deleteAccount(String password) async {
    if (!await verifyPassword(password)) throw AuthException('Password is incorrect.');
    _accounts.remove(_current);
    _shared.verifiedEmails.remove(_current);
    _current = null;
  }
}

class _SharedAuthState {
  final Map<String, ({String id, String password})> accounts = {};
  final Set<String> verifiedEmails = {};
  final List<String> sentResets = [];
  int nextId = 1;
}

const kEmailTakenMessage = 'This email already has a login. Log in instead (use "Forgot password?" if needed).';
