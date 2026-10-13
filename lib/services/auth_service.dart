import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../models/app_user.dart';
import 'api_client.dart';
import 'auth_validation.dart';
import 'cart_store.dart';
import 'oauth_launcher.dart';
import 'session_storage.dart';

@immutable
class GoogleSignInResult {
  final bool signedIn;
  final bool redirecting;
  final String? error;
  const GoogleSignInResult.success()
    : signedIn = true,
      redirecting = false,
      error = null;
  const GoogleSignInResult.cancelled()
    : signedIn = false,
      redirecting = false,
      error = null;
  const GoogleSignInResult.redirected()
    : signedIn = false,
      redirecting = true,
      error = null;
  const GoogleSignInResult.failure(String message)
    : signedIn = false,
      redirecting = false,
      error = message;
}

class _AuthSession {
  AppUser? user;
  final events = StreamController<AppUser?>.broadcast();
  Future<void>? initialization;
  bool initialized = false;
  StreamSubscription<Uri>? links;
  Completer<GoogleSignInResult>? google;
  Future<void>? callbackTask;
  String? lastCallback;
  String? lastOAuthError;
}

/// The default instances share one session across customer and merchant views.
/// Test instances inject an HTTP client and storage without native SDK fakes.
class AuthService {
  static final _sharedSession = _AuthSession();
  static final instance = AuthService();
  final ApiClient _api;
  final SessionStorage _storage;
  final OAuthLauncher _oauth;
  final _AuthSession _session;

  AuthService({ApiClient? api, SessionStorage? storage, OAuthLauncher? oauth})
    : _api = api ?? ApiClient.instance,
      _storage = storage ?? SessionStorage.create(),
      _oauth = oauth ?? OAuthLauncher.create(),
      _session = api == null && storage == null && oauth == null
          ? _sharedSession
          : _AuthSession() {
    _api.onUnauthorized = _expireSession;
  }

  AppUser? get currentUser => _session.user;
  String? get lastOAuthError => _session.lastOAuthError;
  static bool requiresEmailVerification(AppUser user) => !user.emailVerified;

  Stream<AppUser?> get userChanges => Stream<AppUser?>.multi((listener) {
    // Subscribe before delivering current state so immediate sign-in is not lost.
    final subscription = _session.events.stream.listen(
      listener.add,
      onError: listener.addError,
    );
    listener.add(_session.user);
    listener.onCancel = subscription.cancel;
  });

  Future<void> initialize() => _session.initialization ??= _initialize()
      .whenComplete(() => _session.initialization = null);

  Future<void> _initialize() async {
    if (_session.initialized) return;
    _api.validateConfiguration();
    // A reachable API is required before rendering an actionable login form.
    await _api.request('GET', '/capabilities');
    _listenForCallbacks();
    final initial = await _oauth.initialCallback();
    if (initial != null && _isCallback(initial)) await _handleCallback(initial);
    final token = await _storage.read('token');
    if (token != null && token.isNotEmpty) {
      _api.bearerToken = token;
      try {
        final data = await _api.request('GET', '/auth/me');
        _setUser(AppUser.fromJson(_object(data)));
      } on ApiException catch (error) {
        if (error.statusCode != 401) rethrow;
        // Only an explicit server rejection clears a saved session.
      }
    }
    _session.initialized = true;
  }

  void _listenForCallbacks() {
    _session.links ??= _oauth.callbacks.listen(
      (uri) => unawaited(_handleCallback(uri)),
      onError: (_) => _completeGoogle(
        const GoogleSignInResult.failure(
          'รับผล Google ไม่ได้ กรุณากลับมาเข้าสู่ระบบอีกครั้ง',
        ),
      ),
    );
  }

  Future<String?> signInWithEmail(String email, String password) async {
    final validation =
        AuthValidation.email(email) ?? AuthValidation.loginPassword(password);
    if (validation != null) return validation;
    return _accountOperation(() async {
      final data = await _api.request(
        'POST',
        '/auth/login',
        body: {
          'email': AuthValidation.normalizeEmail(email),
          'password': password,
          'deviceName': kIsWeb ? 'MSU Food Web' : 'MSU Food App',
        },
      );
      await _acceptSession(data);
    });
  }

  Future<String?> registerWithEmail({
    required String name,
    required String email,
    required String password,
  }) async {
    final validation =
        AuthValidation.name(name) ??
        AuthValidation.email(email) ??
        AuthValidation.password(password);
    if (validation != null) return validation;
    return _accountOperation(() async {
      final data = await _api.request(
        'POST',
        '/auth/register',
        body: {
          'name': name.trim(),
          'email': AuthValidation.normalizeEmail(email),
          'password': password,
          'password_confirmation': password,
        },
      );
      await _acceptSession(data);
    });
  }

  Future<String?> sendPasswordReset(String email) async {
    final validation = AuthValidation.email(email);
    if (validation != null) return validation;
    return _accountOperation(() async {
      await _api.request(
        'POST',
        '/auth/password/forgot',
        body: {'email': AuthValidation.normalizeEmail(email)},
      );
    });
  }

  Future<String?> resetPassword({
    required String email,
    required String token,
    required String password,
  }) async {
    final validation =
        AuthValidation.email(email) ?? AuthValidation.password(password);
    if (validation != null) return validation;
    if (token.trim().isEmpty) return 'ลิงก์เปลี่ยนรหัสผ่านไม่ถูกต้อง';
    return _accountOperation(() async {
      await _api.request(
        'POST',
        '/auth/password/reset',
        body: {
          'email': AuthValidation.normalizeEmail(email),
          'token': token,
          'password': password,
          'password_confirmation': password,
        },
      );
    });
  }

  Future<String?> sendVerificationEmail() async {
    final user = currentUser;
    if (user == null) return 'กรุณาเข้าสู่ระบบอีกครั้ง';
    if (user.emailVerified) return null;
    return _accountOperation(() async {
      await _api.request('POST', '/auth/email/resend');
    });
  }

  Future<String?> refreshUser() async {
    if (currentUser == null) return 'กรุณาเข้าสู่ระบบอีกครั้ง';
    return _accountOperation(() async {
      final data = await _api.request('GET', '/auth/me');
      _setUser(AppUser.fromJson(_object(data)));
    });
  }

  Future<String?> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final validation =
        AuthValidation.loginPassword(currentPassword) ??
        AuthValidation.password(newPassword);
    if (validation != null) return validation;
    if (currentPassword == newPassword) {
      return 'เลือกรหัสผ่านใหม่ที่ต่างจากเดิม';
    }
    if (currentUser == null) return 'กรุณาเข้าสู่ระบบอีกครั้ง';
    if (!currentUser!.hasPassword) {
      return 'จัดการรหัสผ่านผ่านผู้ให้บริการที่ใช้เข้าสู่ระบบ';
    }
    return _accountOperation(() async {
      await _api.request(
        'PUT',
        '/auth/password',
        body: {
          'currentPassword': currentPassword,
          'newPassword': newPassword,
          'newPasswordConfirmation': newPassword,
        },
      );
    });
  }

  Future<String?> signInWithGoogle() async =>
      (await signInWithGoogleResult()).error;

  Future<GoogleSignInResult> signInWithGoogleResult() async {
    if (_session.google != null) return _session.google!.future;
    final pending = Completer<GoogleSignInResult>();
    _session.google = pending;
    _session.lastOAuthError = null;
    _session.lastCallback = null;
    try {
      _listenForCallbacks();
      final verifier = _randomToken();
      final state = _randomToken();
      final challenge = base64Url
          .encode(sha256.convert(ascii.encode(verifier)).bytes)
          .replaceAll('=', '');
      final callback = _oauth.callbackUri;
      await _storage.write(
        'google_pending',
        jsonEncode({
          'state': state,
          'verifier': verifier,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      final query = Uri(
        queryParameters: {
          'redirectUri': callback.toString(),
          'state': state,
          'codeChallenge': challenge,
          'codeChallengeMethod': 'S256',
        },
      ).query;
      final data = _object(
        await _api.request('GET', '/auth/google/start?$query'),
      );
      final url = Uri.tryParse(data['url'] as String? ?? '');
      // The browser may only be opened at an actual Google authorization URL.
      if (url == null ||
          url.scheme != 'https' ||
          url.host != 'accounts.google.com') {
        throw const ApiException(502, 'เซิร์ฟเวอร์ส่งลิงก์ Google ไม่ถูกต้อง');
      }
      if (!await _oauth.open(url)) {
        throw const ApiException(
          0,
          'เปิดเบราว์เซอร์ Google ไม่ได้ กรุณาลองใหม่',
        );
      }
      if (kIsWeb) {
        _session.google = null;
        return const GoogleSignInResult.redirected();
      }
      return await pending.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () => const GoogleSignInResult.failure(
          'ยังไม่ได้รับผล Google กรุณากลับมาเข้าสู่ระบบอีกครั้ง',
        ),
      );
    } catch (error) {
      return GoogleSignInResult.failure(_message(error));
    } finally {
      if (!kIsWeb || _session.google != null) {
        _session.google = null;
        await _storage.delete('google_pending');
      }
    }
  }

  bool _isCallback(Uri uri) {
    final expected = _oauth.callbackUri;
    return uri.scheme == expected.scheme &&
        uri.host == expected.host &&
        uri.port == expected.port &&
        uri.path == expected.path;
  }

  Future<void> _handleCallback(Uri uri) {
    if (!_isCallback(uri)) return Future<void>.value();
    if (_session.callbackTask != null) return _session.callbackTask!;
    if (_session.lastCallback == uri.toString()) return Future<void>.value();
    _session.lastCallback = uri.toString();
    return _session.callbackTask = _exchangeCallback(
      uri,
    ).whenComplete(() => _session.callbackTask = null);
  }

  Future<void> _exchangeCallback(Uri uri) async {
    try {
      final saved = await _storage.read('google_pending');
      if (saved == null) {
        throw const ApiException(
          400,
          'คำขอ Google หมดอายุ กรุณาเข้าสู่ระบบใหม่',
        );
      }
      final pending = _object(jsonDecode(saved));
      final created = DateTime.tryParse(pending['createdAt'] as String? ?? '');
      final elapsed = created == null
          ? null
          : DateTime.now().toUtc().difference(created);
      if (pending['state'] != uri.queryParameters['state'] ||
          elapsed == null ||
          elapsed.isNegative ||
          elapsed > const Duration(minutes: 10)) {
        throw const ApiException(
          400,
          'ข้อมูลยืนยัน Google ไม่ตรงกับคำขอ กรุณาลองใหม่',
        );
      }
      final providerError = uri.queryParameters['error'];
      if (providerError == 'access_denied' || providerError == 'cancelled') {
        _completeGoogle(const GoogleSignInResult.cancelled());
        return;
      }
      if (providerError != null) {
        throw ApiException(400, switch (providerError) {
          'account_link_required' =>
            'อีเมลนี้มีบัญชีเดิมแล้ว กรุณาเข้าสู่ระบบด้วยอีเมลและรหัสผ่าน',
          'email_not_verified' =>
            'บัญชี Google ยังไม่ได้ยืนยันอีเมล กรุณาตรวจสอบบัญชีแล้วลองใหม่',
          _ => 'Google ยืนยันบัญชีไม่สำเร็จ กรุณาลองอีกครั้ง',
        });
      }
      final code = uri.queryParameters['code'];
      if (code == null || code.isEmpty) {
        throw const ApiException(400, 'Google ไม่ได้ส่งรหัสยืนยันบัญชี');
      }
      final data = await _api.request(
        'POST',
        '/auth/google/exchange',
        body: {
          'code': code,
          'state': pending['state'],
          'verifier': pending['verifier'],
        },
      );
      await _acceptSession(data);
      _completeGoogle(const GoogleSignInResult.success());
    } catch (error) {
      _session.lastOAuthError = _message(error);
      _completeGoogle(GoogleSignInResult.failure(_session.lastOAuthError!));
    } finally {
      await _storage.delete('google_pending');
      _oauth.clearCallbackUrl();
    }
  }

  void _completeGoogle(GoogleSignInResult result) {
    if (_session.google?.isCompleted == false) {
      _session.google!.complete(result);
    }
  }

  Future<void> _acceptSession(dynamic data) async {
    final result = _object(data);
    final token = result['token'];
    final user = AppUser.fromJson(_object(result['user']));
    if (token is! String || token.trim().isEmpty) {
      throw const ApiException(502, 'เซิร์ฟเวอร์ไม่ได้ส่งเซสชันสำหรับบัญชีนี้');
    }
    await _storage.write('token', token);
    final oldUid = currentUser?.uid;
    if (oldUid != null && oldUid != user.uid) CartStore.clearAccount(oldUid);
    _api.bearerToken = token;
    _setUser(user);
  }

  Future<void> signOut() async {
    // Confirm revocation before claiming the remote session is closed.
    if (_api.bearerToken != null) {
      try {
        await _api.request('POST', '/auth/logout');
      } on ApiException catch (error) {
        if (error.statusCode != 401) rethrow;
      }
    }
    await _expireSession();
    await _storage.delete('google_pending');
  }

  Future<void> _expireSession() async {
    final uid = currentUser?.uid;
    _api.bearerToken = null;
    _setUser(null);
    if (uid != null) CartStore.clearAccount(uid);
    await _storage.delete('token');
  }

  void _setUser(AppUser? user) {
    _session.user = user;
    _session.events.add(user);
  }

  Future<String?> _accountOperation(Future<void> Function() operation) async {
    try {
      await operation();
      return null;
    } catch (error) {
      return _message(error);
    }
  }

  static Map<String, dynamic> _object(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    throw const ApiException(
      502,
      'เซิร์ฟเวอร์ส่งข้อมูลบัญชีไม่ครบ กรุณาลองใหม่',
    );
  }

  static String _message(Object error) => error is ApiException
      ? error.message
      : 'ดำเนินการไม่สำเร็จ กรุณาตรวจการเชื่อมต่อแล้วลองใหม่';
  static String _randomToken() => base64Url
      .encode(List<int>.generate(32, (_) => Random.secure().nextInt(256)))
      .replaceAll('=', '');
}
