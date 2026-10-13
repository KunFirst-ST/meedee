import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:msu_food2/screens/forgot_password_screen.dart';
import 'package:msu_food2/screens/login_screen.dart';
import 'package:msu_food2/screens/register_screen.dart';
import 'package:msu_food2/services/auth_service.dart';
import 'package:msu_food2/theme/app_theme.dart';
import 'package:msu_food2/widgets/google_sign_in_button.dart';
import 'package:msu_food2/widgets/auth_form_layout.dart';

class _FakeAuthService extends AuthService {
  int loginCalls = 0;
  int googleCalls = 0;
  int registerCalls = 0;
  int resetCalls = 0;
  String? resetEmail;
  Completer<String?>? loginResult;
  Completer<GoogleSignInResult>? googleResult;
  GoogleSignInResult googleOutcome = const GoogleSignInResult.success();
  String? googleError;
  bool throwOnGoogle = false;

  @override
  Future<String?> signInWithEmail(String email, String password) async {
    loginCalls++;
    return loginResult == null ? 'ลองเข้าสู่ระบบอีกครั้ง' : loginResult!.future;
  }

  @override
  Future<GoogleSignInResult> signInWithGoogleResult() async {
    googleCalls++;
    if (throwOnGoogle) throw StateError('Google connection unavailable');
    if (googleResult != null) return googleResult!.future;
    return googleError == null
        ? googleOutcome
        : GoogleSignInResult.failure(googleError!);
  }

  @override
  Future<String?> registerWithEmail({
    required String name,
    required String email,
    required String password,
  }) async {
    registerCalls++;
    return null;
  }

  @override
  Future<String?> sendPasswordReset(String email) async {
    resetCalls++;
    resetEmail = email;
    return null;
  }
}

Future<void> _show(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: screen));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('invalid login never calls account services', (tester) async {
    final auth = _FakeAuthService();
    await _show(tester, LoginScreen(authService: auth));
    await tester.enterText(
      find.byKey(const Key('login-email')),
      'not-an-email',
    );
    await _tap(tester, find.byKey(const Key('login-submit')));
    expect(auth.loginCalls, 0);
    expect(auth.googleCalls, 0);
    expect(find.text('กรุณากรอกอีเมลให้ถูกต้อง'), findsOneWidget);
    expect(find.text('กรุณากรอกรหัสผ่าน'), findsOneWidget);
  });

  testWidgets('login prevents duplicate submits while waiting', (tester) async {
    final auth = _FakeAuthService()..loginResult = Completer<String?>();
    await _show(tester, LoginScreen(authService: auth));
    await tester.enterText(
      find.byKey(const Key('login-email')),
      'student@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('login-password')),
      'secret123',
    );
    final button = find.byKey(const Key('login-submit'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pump();
    expect(auth.loginCalls, 1);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(
      tester
          .widget<GoogleSignInButton>(find.byKey(const Key('login-google')))
          .onPressed,
      isNull,
    );
    auth.loginResult!.complete('ตรวจอินเทอร์เน็ตแล้วลองอีกครั้ง');
    await tester.pumpAndSettle();
    expect(find.text('ตรวจอินเทอร์เน็ตแล้วลองอีกครั้ง'), findsOneWidget);
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
  });

  testWidgets('Google sign-in appears first and bypasses email validation', (
    tester,
  ) async {
    final auth = _FakeAuthService();
    await _show(tester, LoginScreen(authService: auth));
    final google = find.byKey(const Key('login-google'));
    expect(
      tester.getTopLeft(google).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('login-email'))).dy),
    );
    await _tap(tester, google);
    expect(auth.googleCalls, 1);
    expect(auth.loginCalls, 0);
    expect(find.text('กรุณากรอกอีเมล'), findsNothing);
    expect(find.text('กรุณากรอกรหัสผ่าน'), findsNothing);
    // Account routing belongs to AuthGate, not the login form itself.
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(GoogleSignInButton), findsOneWidget);
  });

  testWidgets(
    'pending Google prevents duplicate submits and cancellation restores controls',
    (tester) async {
      final auth = _FakeAuthService()
        ..googleResult = Completer<GoogleSignInResult>();
      await _show(tester, LoginScreen(authService: auth));
      final google = find.byKey(const Key('login-google'));
      await tester.ensureVisible(google);
      await tester.pumpAndSettle();
      await tester.tap(google);
      await tester.pump();
      expect(auth.googleCalls, 1);
      expect(tester.widget<GoogleSignInButton>(google).loading, isTrue);
      expect(tester.widget<GoogleSignInButton>(google).onPressed, isNull);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('login-submit')))
            .onPressed,
        isNull,
      );
      auth.googleResult!.complete(const GoogleSignInResult.cancelled());
      await tester.pumpAndSettle();
      expect(tester.widget<GoogleSignInButton>(google).loading, isFalse);
      expect(tester.widget<GoogleSignInButton>(google).onPressed, isNotNull);
      expect(find.text('เข้าสู่ระบบด้วย Google'), findsOneWidget);
      expect(auth.googleCalls, 1);
      expect(auth.loginCalls, 0);
      const notice =
          'การเข้าสู่ระบบ Google ยังไม่เสร็จสมบูรณ์ กรุณาลองอีกครั้ง';
      expect(find.text(notice), findsOneWidget);
      expect(
        tester
            .widget<AuthNotice>(find.widgetWithText(AuthNotice, notice))
            .isError,
        isFalse,
      );
      expect(find.byType(LoginScreen), findsOneWidget);
    },
  );

  testWidgets(
    'Google errors stay inline and allow retry including thrown failures',
    (tester) async {
      final auth = _FakeAuthService()
        ..googleError = 'เชื่อมต่อ Google ไม่ได้ กรุณาลองใหม่';
      await _show(tester, LoginScreen(authService: auth));
      final google = find.byKey(const Key('login-google'));
      await _tap(tester, google);
      expect(find.text('เชื่อมต่อ Google ไม่ได้ กรุณาลองใหม่'), findsOneWidget);
      expect(
        tester
            .widget<AuthNotice>(
              find.widgetWithText(
                AuthNotice,
                'เชื่อมต่อ Google ไม่ได้ กรุณาลองใหม่',
              ),
            )
            .isError,
        isTrue,
      );
      expect(tester.widget<GoogleSignInButton>(google).onPressed, isNotNull);
      auth.googleError = null;
      await _tap(tester, google);
      expect(find.text('เชื่อมต่อ Google ไม่ได้ กรุณาลองใหม่'), findsNothing);
      auth.throwOnGoogle = true;
      await _tap(tester, google);
      expect(
        find.text(
          'เชื่อมต่อไม่สำเร็จ ตรวจอินเทอร์เน็ตแล้วลองเข้าสู่ระบบอีกครั้ง',
        ),
        findsOneWidget,
      );
      expect(auth.googleCalls, 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('incomplete Google notice clears on retry and email sign-in', (
    tester,
  ) async {
    const notice = 'การเข้าสู่ระบบ Google ยังไม่เสร็จสมบูรณ์ กรุณาลองอีกครั้ง';
    final auth = _FakeAuthService()
      ..googleOutcome = const GoogleSignInResult.cancelled();
    await _show(tester, LoginScreen(authService: auth));
    final google = find.byKey(const Key('login-google'));
    await _tap(tester, google);
    expect(find.text(notice), findsOneWidget);
    auth.googleResult = Completer<GoogleSignInResult>();
    await tester.ensureVisible(google);
    await tester.pumpAndSettle();
    await tester.tap(google);
    await tester.pump();
    expect(find.text(notice), findsNothing);
    auth.googleResult!.complete(const GoogleSignInResult.cancelled());
    await tester.pumpAndSettle();
    expect(find.text(notice), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('login-email')),
      'student@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('login-password')),
      'secret123',
    );
    await _tap(tester, find.byKey(const Key('login-submit')));
    expect(auth.loginCalls, 1);
    expect(find.text(notice), findsNothing);
    expect(find.text('ลองเข้าสู่ระบบอีกครั้ง'), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets(
    'connection notice offers retry and uses the newly provided account service',
    (tester) async {
      const message = 'ระบบบัญชียังเชื่อมต่อไม่ได้ กรุณาลองใหม่';
      final unavailable = _FakeAuthService()..googleError = message;
      final ready = _FakeAuthService();
      var retryCalls = 0;
      var connected = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: StatefulBuilder(
            builder: (context, setState) => LoginScreen(
              authService: connected ? ready : unavailable,
              connectionError: connected ? null : message,
              onRetryConnection: () {
                retryCalls++;
                setState(() => connected = true);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final google = find.byKey(const Key('login-google'));
      expect(find.text(message), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(message)).dy,
        lessThan(tester.getTopLeft(google).dy),
      );
      expect(tester.widget<GoogleSignInButton>(google).onPressed, isNotNull);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('login-submit')))
            .onPressed,
        isNotNull,
      );
      await _tap(tester, google);
      expect(unavailable.googleCalls, 1);
      await _tap(tester, find.byKey(const Key('login-retry-connection')));
      expect(retryCalls, 1);
      await _tap(tester, google);
      expect(ready.googleCalls, 1);
      expect(unavailable.googleCalls, 1);
      expect(find.text(message), findsNothing);
    },
  );

  testWidgets(
    'Google error and connection retry wrap at narrow width with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _show(
        tester,
        LoginScreen(
          authService: _FakeAuthService()
            ..googleError =
                'เชื่อมต่อ Google ไม่ได้ ตรวจอินเทอร์เน็ตและลองอีกครั้ง',
          connectionError:
              'ระบบบัญชียังไม่พร้อมใช้งาน กรุณาตรวจการเชื่อมต่อแล้วลองใหม่',
          onRetryConnection: () {},
        ),
      );
      await _tap(tester, find.byKey(const Key('login-google')));
      expect(
        find.text('เชื่อมต่อ Google ไม่ได้ ตรวจอินเทอร์เน็ตและลองอีกครั้ง'),
        findsOneWidget,
      );
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -1600),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('signup validates confirmation before creating an account', (
    tester,
  ) async {
    final auth = _FakeAuthService();
    await _show(tester, RegisterScreen(authService: auth));
    await tester.enterText(find.byKey(const Key('register-name')), 'นิสิต มมส');
    await tester.enterText(
      find.byKey(const Key('register-email')),
      'student@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('register-password')),
      'secret123',
    );
    await tester.enterText(
      find.byKey(const Key('register-confirmation')),
      'different123',
    );
    await _tap(tester, find.byKey(const Key('register-submit')));
    expect(auth.registerCalls, 0);
    expect(find.text('รหัสผ่านทั้งสองช่องไม่ตรงกัน'), findsOneWidget);
  });

  testWidgets('successful signup returns to the auth gate route', (
    tester,
  ) async {
    final auth = _FakeAuthService();
    await _show(tester, LoginScreen(authService: auth));
    await _tap(tester, find.text('สร้างบัญชี'));
    expect(find.byType(RegisterScreen), findsOneWidget);
    await tester.enterText(find.byKey(const Key('register-name')), 'นิสิต มมส');
    await tester.enterText(
      find.byKey(const Key('register-email')),
      'student@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('register-password')),
      'secret123',
    );
    await tester.enterText(
      find.byKey(const Key('register-confirmation')),
      'secret123',
    );
    await _tap(tester, find.byKey(const Key('register-submit')));
    expect(auth.registerCalls, 1);
    expect(find.byType(RegisterScreen), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets(
    'reset rejects invalid email and uses neutral success with cooldown',
    (tester) async {
      final auth = _FakeAuthService();
      await _show(tester, ForgotPasswordScreen(authService: auth));
      await tester.enterText(
        find.byKey(const Key('reset-email')),
        'not-an-email',
      );
      await _tap(tester, find.byKey(const Key('reset-submit')));
      expect(auth.resetCalls, 0);
      await tester.enterText(
        find.byKey(const Key('reset-email')),
        ' unknown@example.com ',
      );
      await _tap(tester, find.byKey(const Key('reset-submit')));
      expect(auth.resetCalls, 1);
      expect(auth.resetEmail, 'unknown@example.com');
      expect(
        find.textContaining('หากอีเมลนี้มีบัญชี คุณจะได้รับลิงก์'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('reset-submit')))
            .onPressed,
        isNull,
      );
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('reset-submit')))
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'account forms have no demo entry and keep real submission controls enabled',
    (tester) async {
      final auth = _FakeAuthService();
      await _show(tester, LoginScreen(authService: auth));
      expect(find.textContaining('ทดลอง'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('login-submit')))
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<GoogleSignInButton>(find.byKey(const Key('login-google')))
            .onPressed,
        isNotNull,
      );
      await _tap(tester, find.text('สร้างบัญชี'));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('register-submit')))
            .onPressed,
        isNotNull,
      );
      expect(find.textContaining('ทดลอง'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await _tap(tester, find.text('ลืมรหัสผ่าน?'));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('reset-submit')))
            .onPressed,
        isNotNull,
      );
      expect(find.textContaining('ทดลอง'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        auth.loginCalls +
            auth.googleCalls +
            auth.registerCalls +
            auth.resetCalls,
        0,
      );
    },
  );

  testWidgets('all forms scroll at narrow width and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final screen in [
      const LoginScreen(),
      const RegisterScreen(),
      const ForgotPasswordScreen(),
    ]) {
      await _show(tester, screen);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -1600),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
