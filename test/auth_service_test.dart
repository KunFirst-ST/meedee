import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:msu_food2/services/api_client.dart';
import 'package:msu_food2/services/cart_store.dart';
import 'support/api_auth_harness.dart';

void main() {
  test(
    'public HTTP and missing API configuration never send passwords',
    () async {
      for (final url in [
        '',
        'http://103.114.201.109/api/v1',
        'https://user:secret@example.test/api/v1',
      ]) {
        var requests = 0;
        final api = ApiClient(
          baseUrl: url,
          client: MockClient((_) async {
            requests++;
            return success(null);
          }),
        );
        await expectLater(
          api.request('POST', '/auth/login', body: {'password': 'never-send'}),
          throwsA(isA<ApiException>()),
        );
        expect(requests, 0);
      }
    },
  );

  test(
    'HTTP redirects and HTML responses cannot become successful auth',
    () async {
      for (final response in [
        http.Response('<html>proxy</html>', 200),
        http.Response('', 302),
      ]) {
        final h = Harness((_) => response);
        expect(
          await h.auth.signInWithEmail('student@example.com', 'secret123'),
          isNotNull,
        );
        expect(h.auth.currentUser, isNull);
        expect(h.api.bearerToken, isNull);
        expect(h.storage.values['token'], isNull);
      }
    },
  );

  test(
    'login accepts canonical API identity and securely saves bearer before emitting',
    () async {
      final h = Harness((request) {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/auth/login');
        expect(jsonDecode(request.body)['email'], 'student@example.com');
        return success({'token': 'sanctum-token', 'user': user()});
      });
      final events = <String?>[];
      final subscription = h.auth.userChanges.listen((u) {
        events.add(u?.uid);
        if (u != null) expect(h.storage.values['token'], 'sanctum-token');
      });
      expect(
        await h.auth.signInWithEmail(' Student@example.com ', 'secret123'),
        isNull,
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, [null, 'api-user']);
      expect(h.api.bearerToken, 'sanctum-token');
      expect(h.auth.currentUser?.emailVerified, isTrue);
      await subscription.cancel();
    },
  );

  test(
    'malformed success missing token or user never opens a session',
    () async {
      for (final data in [
        {'user': user()},
        {'token': 'token'},
        {
          'token': 'token',
          'user': {'email': 'missing-id'},
        },
      ]) {
        final h = Harness((_) => success(data));
        expect(
          await h.auth.signInWithEmail('student@example.com', 'secret123'),
          isNotNull,
        );
        expect(h.auth.currentUser, isNull);
        expect(h.storage.values['token'], isNull);
      }
    },
  );

  test(
    'invalid login and password confirmation validations do not call API',
    () async {
      final h = Harness((_) => success(null));
      expect(await h.auth.signInWithEmail('invalid', ''), isNotNull);
      expect(
        await h.auth.registerWithEmail(
          name: 'Student',
          email: 'student@example.com',
          password: 'short',
        ),
        isNotNull,
      );
      expect(h.requests, isEmpty);
    },
  );

  test(
    'signup is unverified and verification requires a fresh server acknowledgement',
    () async {
      var verified = false;
      final h = Harness((r) {
        if (r.url.path.endsWith('/auth/register')) {
          final body = jsonDecode(r.body);
          expect(body['password_confirmation'], body['password']);
          return success({
            'token': 'registered-token',
            'user': user(verified: false),
          });
        }
        if (r.url.path.endsWith('/auth/email/resend')) {
          return failure(503, 'Mail is unavailable');
        }
        return success(user(verified: verified));
      });
      expect(
        await h.auth.registerWithEmail(
          name: 'Student',
          email: 'student@example.com',
          password: 'secret123',
        ),
        isNull,
      );
      expect(h.auth.currentUser?.emailVerified, isFalse);
      expect(await h.auth.sendVerificationEmail(), 'Mail is unavailable');
      expect(await h.auth.refreshUser(), isNull);
      expect(h.auth.currentUser?.emailVerified, isFalse);
      verified = true;
      expect(await h.auth.refreshUser(), isNull);
      expect(h.auth.currentUser?.emailVerified, isTrue);
    },
  );

  test(
    'restored sessions are verified with me, never with saved user JSON',
    () async {
      final h = Harness((r) {
        expect(r.headers['authorization'], 'Bearer stored-token');
        return success(user());
      });
      h.storage.values['token'] = 'stored-token';
      expect(h.auth.currentUser, isNull);
      await h.auth.initialize();
      expect(h.auth.currentUser?.uid, 'api-user');
      expect(h.requests.map((r) => r.url.path), contains('/api/v1/auth/me'));
    },
  );

  test(
    'a lost connection preserves token for retry without claiming restored login',
    () async {
      final h = Harness((_) => failure(503, 'Offline'));
      h.storage.values['token'] = 'stored-token';
      await expectLater(h.auth.initialize(), throwsA(isA<ApiException>()));
      expect(h.auth.currentUser, isNull);
      expect(h.storage.values['token'], 'stored-token');
    },
  );

  test('server 401 clears session and every account cart', () async {
    var reject = false;
    final h = Harness(
      (r) => reject
          ? failure(401, 'Expired')
          : success({'token': 'token', 'user': user()}),
    );
    await h.auth.signInWithEmail('student@example.com', 'secret123');
    CartStore.forShop('api-user', 'shop-a').setQuantity('rice', 1);
    CartStore.forShop('api-user', 'shop-b').setQuantity('rice', 2);
    reject = true;
    expect(await h.auth.refreshUser(), 'Expired');
    expect(h.auth.currentUser, isNull);
    expect(h.api.bearerToken, isNull);
    expect(h.storage.values['token'], isNull);
    expect(CartStore.forShop('api-user', 'shop-a').count, 0);
    expect(CartStore.forShop('api-user', 'shop-b').count, 0);
    CartStore.clearAccount('api-user');
  });

  test(
    'logout waits for revocation and does not claim success on server failure',
    () async {
      var reject = true;
      final h = Harness((r) {
        if (r.url.path.endsWith('/auth/logout')) {
          expect(r.headers['authorization'], 'Bearer token');
          return reject ? failure(503, 'Offline') : success(null);
        }
        return success({'token': 'token', 'user': user()});
      });
      await h.auth.signInWithEmail('student@example.com', 'secret123');
      await expectLater(h.auth.signOut(), throwsA(isA<ApiException>()));
      expect(h.auth.currentUser, isNotNull);
      reject = false;
      await h.auth.signOut();
      expect(h.auth.currentUser, isNull);
      expect(h.storage.values['token'], isNull);
    },
  );

  test(
    'password change uses current password and backend only after validation',
    () async {
      final h = Harness((r) {
        if (r.url.path.endsWith('/auth/password')) {
          expect(r.method, 'PUT');
          expect(jsonDecode(r.body), {
            'currentPassword': 'current123',
            'newPassword': 'updated123',
            'newPasswordConfirmation': 'updated123',
          });
          return success(null);
        }
        return success({'token': 'token', 'user': user()});
      });
      await h.auth.signInWithEmail('student@example.com', 'secret123');
      expect(
        await h.auth.changePassword(
          currentPassword: 'current123',
          newPassword: 'current123',
        ),
        isNotNull,
      );
      expect(h.requests, hasLength(1));
      expect(
        await h.auth.changePassword(
          currentPassword: 'current123',
          newPassword: 'updated123',
        ),
        isNull,
      );
      expect(h.requests, hasLength(2));
    },
  );

  test(
    'unavailable reset mail is an error instead of fake delivery success',
    () async {
      final h = Harness((r) {
        expect(jsonDecode(r.body)['email'], 'student@example.com');
        return failure(503, 'Configure SMTP');
      });
      expect(
        await h.auth.sendPasswordReset(' Student@example.com '),
        'Configure SMTP',
      );
    },
  );

  test('Google PKCE exchanges a single code and emits a real API user', () async {
    late Harness h;
    String? state;
    String? challenge;
    var exchanges = 0;
    h = Harness((r) {
      if (r.url.path.endsWith('/auth/google/start')) {
        state = r.url.queryParameters['state'];
        challenge = r.url.queryParameters['codeChallenge'];
        expect(r.url.queryParameters['redirectUri'], 'msufood://auth/callback');
        expect(r.url.queryParameters['codeChallengeMethod'], 'S256');
        return success({
          'url':
              'https://accounts.google.com/o/oauth2/v2/auth?state=server-state',
        });
      }
      if (r.url.path.endsWith('/auth/google/exchange')) {
        exchanges++;
        final body = jsonDecode(r.body);
        expect(body['state'], state);
        expect(body['code'], 'single-use-code');
        expect(
          base64Url
              .encode(
                sha256.convert(ascii.encode(body['verifier'] as String)).bytes,
              )
              .replaceAll('=', ''),
          challenge,
        );
        expect(r.url.queryParameters.containsKey('token'), isFalse);
        return success({
          'token': 'google-session',
          'user': user(provider: 'google'),
        });
      }
      throw StateError('Unexpected request');
    });
    await h.auth.initialize();
    h.browser.onOpen = () {
      final callback = Uri.parse(
        'msufood://auth/callback?code=single-use-code&state=$state',
      );
      h.browser.links.add(callback);
      h.browser.links.add(callback);
    };
    final result = await h.auth.signInWithGoogleResult();
    expect(result.signedIn, isTrue);
    expect(exchanges, 1);
    expect(h.auth.currentUser?.providers, ['google']);
    expect(h.storage.values['google_pending'], isNull);
    expect(h.api.bearerToken, 'google-session');
  });

  test(
    'Google callback with wrong state never sends a code exchange',
    () async {
      final h = Harness(
        (r) => success({'url': 'https://accounts.google.com/o/oauth2/v2/auth'}),
      );
      await h.auth.initialize();
      h.browser.onOpen = () => h.browser.links.add(
        Uri.parse('msufood://auth/callback?code=attacker&state=wrong'),
      );
      final result = await h.auth.signInWithGoogleResult();
      expect(result.signedIn, isFalse);
      expect(result.error, isNotNull);
      expect(
        h.requests.where((r) => r.url.path.endsWith('/exchange')),
        isEmpty,
      );
      expect(h.auth.currentUser, isNull);
    },
  );

  test(
    'missing server Google configuration never opens an external browser',
    () async {
      final h = Harness((_) => failure(503, 'Google OAuth is not configured'));
      final result = await h.auth.signInWithGoogleResult();
      expect(result.error, 'Google OAuth is not configured');
      expect(result.signedIn, isFalse);
      expect(h.browser.opened, isNull);
      expect(h.storage.values['google_pending'], isNull);
    },
  );

  test(
    'server Google cancellation is neutral and never exchanges credentials',
    () async {
      late Harness h;
      String? state;
      h = Harness((r) {
        state = r.url.queryParameters['state'];
        return success({'url': 'https://accounts.google.com/o/oauth2/v2/auth'});
      });
      h.browser.onOpen = () => h.browser.links.add(
        Uri.parse('msufood://auth/callback?error=cancelled&state=$state'),
      );
      final result = await h.auth.signInWithGoogleResult();
      expect(result.signedIn, isFalse);
      expect(result.error, isNull);
      expect(h.auth.currentUser, isNull);
      expect(
        h.requests.where((r) => r.url.path.endsWith('/exchange')),
        isEmpty,
      );
    },
  );

  test(
    'cold-start Google callback exchanges securely before restoring server identity',
    () async {
      var exchanges = 0;
      final h = Harness((r) {
        if (r.url.path.endsWith('/auth/google/exchange')) {
          exchanges++;
          expect(jsonDecode(r.body)['verifier'], 'v' * 43);
          return success({
            'token': 'cold-session',
            'user': user(provider: 'google'),
          });
        }
        expect(r.url.path, '/api/v1/auth/me');
        expect(r.headers['authorization'], 'Bearer cold-session');
        return success(user(provider: 'google'));
      });
      h.storage.values['google_pending'] = jsonEncode({
        'state': 's' * 43,
        'verifier': 'v' * 43,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });
      h.browser.initial = Uri.parse(
        'msufood://auth/callback?code=${'c' * 64}&state=${'s' * 43}',
      );
      expect(h.auth.currentUser, isNull);
      await h.auth.initialize();
      h.browser.links.add(h.browser.initial!);
      await Future<void>.delayed(Duration.zero);
      expect(exchanges, 1);
      expect(h.auth.currentUser?.uid, 'api-user');
      expect(h.storage.values['google_pending'], isNull);
      expect(h.auth.lastOAuthError, isNull);
    },
  );
}
