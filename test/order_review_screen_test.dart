import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:msu_food2/models/food_order.dart';
import 'package:msu_food2/screens/customer/order_track_screen.dart';
import 'package:msu_food2/services/db.dart';

class _ReviewDatabase extends Fake implements Db {
  FoodOrder order = FoodOrder(
    id: 'order-1',
    shopId: 'shop-1',
    shopName: 'Hot food',
    customerId: 'customer-1',
    customerName: 'Student',
    items: [OrderItem(name: 'Hotdog', price: 20, qty: 2)],
    total: 40,
    status: OrderStatus.completed,
    note: '',
  );
  final _changes = StreamController<FoodOrder>.broadcast();
  int? submittedRating;
  String? submittedComment;

  @override
  Stream<FoodOrder> watchOrder(String orderId) =>
      Stream<FoodOrder>.multi((controller) {
        controller.add(order);
        final subscription = _changes.stream.listen(controller.add);
        controller.onCancel = subscription.cancel;
      });

  @override
  Future<void> reviewOrder(
    String orderId, {
    required int rating,
    required String comment,
  }) async {
    submittedRating = rating;
    submittedComment = comment;
    order = FoodOrder(
      id: order.id,
      shopId: order.shopId,
      shopName: order.shopName,
      customerId: order.customerId,
      customerName: order.customerName,
      items: order.items,
      total: order.total,
      status: order.status,
      note: order.note,
      review: OrderReview(rating: rating, comment: comment),
    );
    _changes.add(order);
  }
}

void main() {
  testWidgets(
    'submitting a review keeps its text controller alive through dialog close',
    (tester) async {
      final database = _ReviewDatabase();
      addTearDown(database._changes.close);

      await tester.pumpWidget(
        MaterialApp(
          home: OrderTrackScreen(orderId: 'order-1', database: database),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -1600));
      await tester.pumpAndSettle();

      await tester.tap(find.text('ให้คะแนนร้านนี้'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('4 ดาว'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'อร่อยมาก');
      await tester.pump();
      await tester.tap(find.text('ส่งรีวิว'));
      await tester.pumpAndSettle();

      expect(database.submittedRating, 4);
      expect(database.submittedComment, 'อร่อยมาก');
      expect(find.text('ขอบคุณที่รีวิว'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
