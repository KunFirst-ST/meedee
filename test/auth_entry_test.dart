import 'dart:async';
import 'package:msu_food2/models/app_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:msu_food2/main.dart';
import 'package:msu_food2/screens/auth_gate.dart';
import 'package:msu_food2/screens/customer/shop_list_screen.dart';
import 'package:msu_food2/screens/login_screen.dart';
import 'package:msu_food2/screens/register_screen.dart';
import 'package:msu_food2/services/auth_service.dart';
import 'package:msu_food2/widgets/google_sign_in_button.dart';

class _SignedOutAuth extends AuthService {
  @override
  Stream<AppUser?> get userChanges => Stream<AppUser?>.value(null);
}

void main() {
  testWidgets('signed-out app requires login with no guest entry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MsuFoodApp(apiReady: true, authService: _SignedOutAuth()),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AuthGate), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(ShopListScreen), findsNothing);
    expect(find.textContaining('ทดลอง'), findsNothing);
    expect(
      tester
          .widget<GoogleSignInButton>(find.byKey(const Key('login-google')))
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('login-submit')))
          .onPressed,
      isNotNull,
    );
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.routes?.containsKey('/demo') ?? false, isFalse);
    expect(app.routes?.containsKey('/login-preview') ?? false, isFalse);
    await tester.ensureVisible(find.text('สร้างบัญชี'));
    await tester.tap(find.text('สร้างบัญชี'));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsOneWidget);
    expect(find.textContaining('ทดลอง'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing configuration cannot reveal food data', (tester) async {
    await tester.pumpWidget(const MsuFoodApp());
    await tester.pumpAndSettle();
    expect(find.text('ระบบบัญชียังไม่พร้อมใช้งาน'), findsOneWidget);
    expect(find.text('เชื่อมต่ออีกครั้ง'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.byType(GoogleSignInButton), findsNothing);
    expect(find.byType(ShopListScreen), findsNothing);
    expect(find.textContaining('ทดลอง'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed connection can retry through AuthGate without bypass', (
    tester,
  ) async {
    var attempts = 0;
    var connection = Completer<void>();
    await tester.pumpWidget(
      MsuFoodApp(
        authService: _SignedOutAuth(),
        initializeApi: () {
          attempts++;
          return connection.future;
        },
      ),
    );
    await tester.pumpAndSettle();
    final retry = find.text('เชื่อมต่ออีกครั้ง');
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pump();
    expect(attempts, 1);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is AbsorbPointer && w.absorbing),
      findsOneWidget,
    );
    connection.completeError(StateError('connection unavailable'));
    await tester.pumpAndSettle();
    expect(find.byType(AuthGate), findsNothing);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    connection = Completer<void>();
    await tester.tap(retry);
    await tester.pump();
    connection.complete();
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.byType(AuthGate), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(retry, findsNothing);
    expect(find.byType(ShopListScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
