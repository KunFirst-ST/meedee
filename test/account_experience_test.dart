import 'dart:async';

import 'package:msu_food2/models/app_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:msu_food2/screens/account/account_help_sheet.dart';
import 'package:msu_food2/screens/account/account_security_screen.dart';
import 'package:msu_food2/services/auth_service.dart';
import 'package:msu_food2/theme/app_theme.dart';

class _AccountUser extends AppUser {
  _AccountUser(String provider)
    : super(
        uid: 'signed-in-account',
        email: 'student@example.com',
        emailVerified: true,
        providers: [provider == 'google.com' ? 'google' : provider],
      );
}

class _AccountAuth extends AuthService {
  final events = StreamController<AppUser?>.broadcast();
  int passwordChanges = 0;
  String? currentPassword;
  String? newPassword;

  @override
  Stream<AppUser?> get userChanges => events.stream;

  @override
  Future<String?> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    passwordChanges++;
    this.currentPassword = currentPassword;
    this.newPassword = newPassword;
    return null;
  }
}

void main() {
  testWidgets(
    'Google account hides password controls and clears on session loss',
    (tester) async {
      final user = _AccountUser('google.com');
      final auth = _AccountAuth();
      addTearDown(auth.events.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AccountSecurityScreen(user: user, authService: auth),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ยืนยันอีเมลแล้ว'), findsOneWidget);
      expect(find.text('จัดการรหัสผ่านผ่าน Google'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.textContaining('โหมดทดลอง'), findsNothing);
      expect(find.text('student@example.com'), findsOneWidget);

      auth.events.add(null);
      await tester.pumpAndSettle();
      expect(find.text('เซสชันบัญชีสิ้นสุดแล้ว'), findsOneWidget);
      expect(find.text('student@example.com'), findsNothing);
      expect(find.text('จัดการรหัสผ่านผ่าน Google'), findsNothing);
      expect(auth.passwordChanges, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('password confirmation blocks changes until the form is valid', (
    tester,
  ) async {
    final auth = _AccountAuth();
    addTearDown(auth.events.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AccountSecurityScreen(
          user: _AccountUser('password'),
          authService: auth,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(3));
    await tester.ensureVisible(fields.at(0));
    await tester.enterText(fields.at(0), 'current-password');
    await tester.ensureVisible(fields.at(1));
    await tester.enterText(fields.at(1), 'new-password');
    await tester.ensureVisible(fields.at(2));
    await tester.enterText(fields.at(2), 'different-password');
    await tester.ensureVisible(find.text('บันทึกรหัสผ่านใหม่'));
    await tester.tap(find.text('บันทึกรหัสผ่านใหม่'));
    await tester.pumpAndSettle();
    expect(find.text('รหัสผ่านทั้งสองช่องไม่ตรงกัน'), findsOneWidget);
    expect(auth.passwordChanges, 0);

    await tester.ensureVisible(fields.at(2));
    await tester.enterText(fields.at(2), 'new-password');
    await tester.ensureVisible(find.text('บันทึกรหัสผ่านใหม่'));
    await tester.tap(find.text('บันทึกรหัสผ่านใหม่'));
    await tester.pumpAndSettle();
    expect(auth.passwordChanges, 1);
    expect(auth.currentPassword, 'current-password');
    expect(auth.newPassword, 'new-password');
    for (final field in tester.widgetList<TextFormField>(fields)) {
      expect(field.controller!.text, isEmpty);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pickup help works at narrow width and larger text without demo content',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showAccountHelp(context),
                  child: const Text('วิธีใช้งาน'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('วิธีใช้งาน'));
      await tester.pumpAndSettle();
      expect(find.text('สั่งแล้วรับอาหารที่ร้าน'), findsOneWidget);
      expect(find.text('ชำระเงินกับร้าน'), findsOneWidget);
      expect(find.text('ติดตามและยกเลิกออเดอร์'), findsOneWidget);
      expect(find.textContaining('โหมดทดลอง'), findsNothing);
      await tester.ensureVisible(find.text('เข้าใจแล้ว'));
      await tester.tap(find.text('เข้าใจแล้ว'));
      await tester.pumpAndSettle();
      expect(find.text('วิธีใช้งาน'), findsOneWidget);
      expect(find.text('ใช้งาน MSU FOOD'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
