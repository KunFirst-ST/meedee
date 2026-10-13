import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:msu_food2/main.dart';
import 'package:msu_food2/screens/auth_gate.dart';
import 'package:msu_food2/screens/email_verification_screen.dart';
import 'package:msu_food2/screens/login_screen.dart';
import 'package:msu_food2/theme/app_theme.dart';
import 'support/api_auth_harness.dart';

void main() {
  testWidgets('401 closes private pushed routes before returning to login', (
    tester,
  ) async {
    var reject = false;
    final h = Harness(
      (_) => reject
          ? failure(401, 'Expired')
          : success({'token': 'token', 'user': user(verified: false)}),
    );
    await h.auth.signInWithEmail('student@example.com', 'secret123');
    await tester.pumpWidget(MsuFoodApp(apiReady: true, authService: h.auth));
    await tester.pumpAndSettle();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    app.navigatorKey!.currentState!.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Private account details')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Private account details'), findsOneWidget);
    reject = true;
    await h.auth.refreshUser();
    await tester.pumpAndSettle();
    expect(find.text('Private account details'), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(app.navigatorKey!.currentState!.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'verified login advances AuthGate and 401 brings it back to login',
    (tester) async {
      var reject = false;
      final h = Harness(
        (r) => reject
            ? failure(401, 'Expired')
            : success({'token': 'token', 'user': user()}),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AuthGate(
            authService: h.auth,
            authenticatedBuilder: (u) =>
                Scaffold(body: Text('Authenticated ${u.uid}')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      await h.auth.signInWithEmail('student@example.com', 'secret123');
      await tester.pumpAndSettle();
      expect(find.text('Authenticated api-user'), findsOneWidget);
      reject = true;
      await h.auth.refreshUser();
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Authenticated api-user'), findsNothing);
    },
  );

  testWidgets(
    'unverified signup cannot expose authenticated business screens',
    (tester) async {
      final h = Harness(
        (_) => success({'token': 'token', 'user': user(verified: false)}),
      );
      await h.auth.registerWithEmail(
        name: 'Student',
        email: 'student@example.com',
        password: 'secret123',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AuthGate(
            authService: h.auth,
            authenticatedBuilder: (_) => const Text('Business data'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EmailVerificationScreen), findsOneWidget);
      expect(find.text('Business data'), findsNothing);
      expect(find.text('student@example.com'), findsOneWidget);
    },
  );
}
