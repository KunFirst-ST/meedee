import 'dart:async';
import 'package:msu_food2/models/app_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:msu_food2/screens/account/edit_profile_screen.dart';
import 'package:msu_food2/services/db.dart';
import 'package:msu_food2/theme/app_theme.dart';

class _User extends Fake implements AppUser {
  @override
  String get uid => 'real-profile-owner';
  @override
  String? get email => 'owner@example.com';
  @override
  String? get displayName => 'เจ้าของบัญชี';
}

class _ProfileDb extends Fake implements Db {
  final writes = <Completer<void>>[];
  final names = <String>[];
  final phones = <String>[];

  @override
  Stream<Map<String, dynamic>?> watchProfile(String uid) => Stream.value({
    'displayName': 'ชื่อเดิม',
    'phone': '0812345678',
    'role': 'customer',
  });

  @override
  Future<void> updateProfile(
    String uid, {
    required String displayName,
    required String phone,
  }) {
    names.add(displayName);
    phones.add(phone);
    final pending = Completer<void>();
    writes.add(pending);
    return pending.future;
  }
}

Future<GlobalKey<NavigatorState>> _openEditor(
  WidgetTester tester,
  _ProfileDb db,
) async {
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      theme: AppTheme.light,
      home: const Scaffold(body: Text('account home')),
    ),
  );
  navigator.currentState!.push<void>(
    MaterialPageRoute<void>(
      builder: (_) => EditProfileScreen(user: _User(), db: db),
    ),
  );
  await tester.pumpAndSettle();
  return navigator;
}

Future<void> _startSave(WidgetTester tester) async {
  final save = find.byKey(const Key('profile-save'));
  await tester.ensureVisible(save);
  await tester.pumpAndSettle();
  await tester.tap(save);
  await tester.pump();
}

void main() {
  testWidgets('profile success requires a server acknowledgement', (
    tester,
  ) async {
    final db = _ProfileDb();
    await _openEditor(tester, db);
    await tester.enterText(find.byType(TextFormField).first, 'ชื่อใหม่');
    await _startSave(tester);
    expect(db.writes, hasLength(1));
    expect(db.names, ['ชื่อใหม่']);
    expect(find.text('บันทึกข้อมูลบัญชีแล้ว'), findsNothing);
    expect(
      tester.widget<PopScope>(find.byType(PopScope).first).canPop,
      isFalse,
    );
    db.writes.single.complete();
    await tester.pumpAndSettle();
    expect(find.byType(EditProfileScreen), findsNothing);
    expect(find.text('account home'), findsOneWidget);
    expect(find.text('บันทึกข้อมูลบัญชีแล้ว'), findsOneWidget);
  });

  for (final lateFailure in [false, true]) {
    testWidgets(
      'profile timeout unlocks back and ignores late ${lateFailure ? 'failure' : 'acknowledgement'} after disposal',
      (tester) async {
        final db = _ProfileDb();
        final navigator = await _openEditor(tester, db);
        await tester.enterText(
          find.byType(TextFormField).first,
          'ชื่อที่ยังไม่ยืนยัน',
        );
        await _startSave(tester);
        await tester.pump(const Duration(seconds: 19));
        expect(find.textContaining('ยังยืนยันผลการบันทึกไม่ได้'), findsNothing);
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('ยังยืนยันผลการบันทึกไม่ได้'),
          findsOneWidget,
        );
        expect(
          find.textContaining('ข้อมูลอาจถูกบันทึกภายหลัง'),
          findsOneWidget,
        );
        expect(find.text('บันทึกข้อมูลบัญชีแล้ว'), findsNothing);
        expect(
          tester.widget<PopScope>(find.byType(PopScope).first).canPop,
          isTrue,
        );
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('profile-save')))
              .onPressed,
          isNotNull,
        );
        expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).first)
              .controller!
              .text,
          'ชื่อที่ยังไม่ยืนยัน',
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(EditProfileScreen), findsNothing);
        navigator.currentState!.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('unrelated route')),
          ),
        );
        await tester.pumpAndSettle();
        if (lateFailure) {
          db.writes.single.completeError(StateError('Late rejected write'));
        } else {
          db.writes.single.complete();
        }
        await tester.pumpAndSettle();
        expect(find.text('unrelated route'), findsOneWidget);
        expect(find.text('บันทึกข้อมูลบัญชีแล้ว'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'profile can retry after timeout and only the new acknowledgement closes it',
    (tester) async {
      final db = _ProfileDb();
      await _openEditor(tester, db);
      await _startSave(tester);
      await tester.pump(const Duration(seconds: 20));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'แก้ไขหลังลองใหม่',
      );
      await _startSave(tester);
      expect(db.writes, hasLength(2));
      db.writes.first.complete();
      await tester.pump();
      expect(find.byType(EditProfileScreen), findsOneWidget);
      expect(find.text('บันทึกข้อมูลบัญชีแล้ว'), findsNothing);
      db.writes.last.complete();
      await tester.pumpAndSettle();
      expect(find.byType(EditProfileScreen), findsNothing);
      expect(find.text('บันทึกข้อมูลบัญชีแล้ว'), findsOneWidget);
      expect(db.names.last, 'แก้ไขหลังลองใหม่');
    },
  );
}
