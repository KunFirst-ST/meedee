import 'package:msu_food2/models/app_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:msu_food2/models/food_order.dart';
import 'package:msu_food2/models/menu_item.dart';
import 'package:msu_food2/models/shop.dart';
import 'package:msu_food2/screens/customer/checkout_screen.dart';
import 'package:msu_food2/services/cart_store.dart';
import 'package:msu_food2/services/db.dart';
import 'package:msu_food2/theme/app_theme.dart';

class _CheckoutUser extends Fake implements AppUser {
  @override
  String get uid => 'checkout-customer';
  @override
  String? get displayName => 'Customer';
}

class _CheckoutDatabase extends Fake implements Db {
  final shop = Shop(
    id: 'checkout-shop',
    name: 'Shop',
    ownerId: 'shop-owner',
    isOpen: true,
    location: 'จุดรับอาหาร',
    preparationMinutes: 10,
  );
  final item = MenuItem(
    id: 'rice',
    name: 'ข้าว',
    price: 50,
    available: true,
    shopId: 'checkout-shop',
  );
  late FoodOrder order;
  int placedOrders = 0;

  @override
  Stream<Shop> watchShop(String shopId) => Stream.value(shop);

  @override
  Stream<List<MenuItem>> watchMenu(String shopId) => Stream.value([item]);

  @override
  Stream<FoodOrder> watchOrder(String orderId) => Stream.value(order);

  @override
  Future<String> placeOrder({
    required Shop shop,
    required String customerId,
    required String customerName,
    required List<OrderItem> items,
    required String note,
    String? requestId,
  }) async {
    placedOrders++;
    order = FoodOrder(
      id: 'confirmed-order',
      shopId: shop.id,
      shopName: shop.name,
      customerId: customerId,
      customerName: customerName,
      items: items,
      total: OrderValidation.totalFor(items),
      status: OrderStatus.pending,
      note: note,
    );
    return order.id;
  }
}

void main() {
  testWidgets(
    'successful checkout preserves the active cart for the next shop visit',
    (tester) async {
      final user = _CheckoutUser();
      final database = _CheckoutDatabase();
      addTearDown(() => CartStore.clearAccount(user.uid));
      final menuDraft = CartStore.forShop(user.uid, database.shop.id);
      menuDraft.setQuantity(database.item.id, 2);
      final previousRequest = menuDraft.requestId;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => CheckoutScreen(
                        user: user,
                        shop: database.shop,
                        draft: CartStore.forShop(user.uid, database.shop.id),
                        database: database,
                      ),
                    ),
                  ),
                  child: const Text('เปิดตะกร้าของร้าน'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('เปิดตะกร้าของร้าน'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ยืนยันสั่งซื้อ • ฿100'));
      await tester.pumpAndSettle();
      expect(find.text('ติดตามออเดอร์'), findsOneWidget);
      expect(database.placedOrders, 1);
      expect(menuDraft.count, 0);
      expect(menuDraft.requestId, isNot(previousRequest));
      expect(CartStore.forShop(user.uid, database.shop.id), same(menuDraft));

      // The menu that was already open continues to edit its existing draft.
      menuDraft.setQuantity(database.item.id, 3);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('เปิดตะกร้าของร้าน'));
      await tester.pumpAndSettle();
      expect(find.text('ยืนยันสั่งซื้อ • ฿150'), findsOneWidget);
      expect(CartStore.forShop(user.uid, database.shop.id).count, 3);
      expect(database.placedOrders, 1);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'cart drafts keep separate accounts and shops with bounded quantities',
    () {
      final first = CartStore.forShop('customer-a', 'shop-one');
      first.setQuantity('rice', 2);
      expect(CartStore.forShop('customer-a', 'shop-one').quantity('rice'), 2);
      expect(CartStore.forShop('customer-a', 'shop-two').count, 0);
      expect(CartStore.forShop('customer-b', 'shop-one').count, 0);
      first.setQuantity('rice', 21);
      expect(first.quantity('rice'), 2);
      first.setQuantity('rice', 0);
      expect(first.quantities, isEmpty);
      CartStore.clearAccount('customer-a');
      CartStore.clearAccount('customer-b');
    },
  );

  test(
    'checkout request stays stable through edits and rotates after clearing',
    () {
      final draft = CartDraft();
      final requestId = draft.requestId;
      draft.setQuantity('rice', 1);
      draft.note = 'ไม่ใส่พริก';
      expect(draft.requestId, requestId);
      expect(RegExp(r'^[a-f0-9]{32}$').hasMatch(requestId), isTrue);
      expect(CartDraft().requestId, isNot(requestId));
      draft.clear();
      expect(draft.requestId, isNot(requestId));
      expect(draft.quantities, isEmpty);
      expect(draft.note, isEmpty);
    },
  );

  test('signing out removes all own drafts and preserves other accounts', () {
    final other = CartStore.forShop('customer-other', 'shop-one');
    other.setQuantity('rice', 3);
    CartStore.forShop('customer-own', 'shop-one').setQuantity('rice', 1);
    CartStore.forShop('customer-own', 'shop-two').setQuantity('soup', 2);
    CartStore.clearAccount('customer-own');
    expect(CartStore.forShop('customer-own', 'shop-one').count, 0);
    expect(CartStore.forShop('customer-own', 'shop-two').count, 0);
    expect(other.quantity('rice'), 3);
    CartStore.clearAccount('customer-own');
    CartStore.clearAccount('customer-other');
  });
}
