import 'package:flutter_test/flutter_test.dart';
import 'package:msu_food2/models/food_order.dart';
import 'package:msu_food2/models/menu_item.dart';
import 'package:msu_food2/services/db.dart';

OrderItem line({String? id = 'menu', num price = 49, int qty = 1}) =>
    OrderItem(menuItemId: id, name: 'ข้าวผัด', price: price, qty: qty);

void main() {
  final invalid = throwsA(isA<OrderValidationException>());

  test(
    'money totals use integer satang without accumulating floating error',
    () {
      expect(
        OrderValidation.totalFor([
          line(id: 'a', price: 0.1, qty: 3),
          line(id: 'b', price: 0.2, qty: 1),
          line(id: 'c', price: 0.29, qty: 2),
        ]),
        1.08,
      );
    },
  );

  test(
    'rejects empty carts, missing IDs, duplicate lines and invalid counts',
    () {
      expect(() => OrderValidation.totalFor([]), invalid);
      expect(() => OrderValidation.totalFor([line(id: null)]), invalid);
      expect(
        () => OrderValidation.totalFor([line(id: 'invalid/path')]),
        invalid,
      );
      expect(() => OrderValidation.totalFor([line(), line()]), invalid);
      expect(() => OrderValidation.totalFor([line(qty: 0)]), invalid);
      expect(() => OrderValidation.totalFor([line(qty: -1)]), invalid);
      expect(() => OrderValidation.totalFor([line(qty: 100)]), invalid);
    },
  );

  test('keeps checkout within the Firestore validation access budget', () {
    expect(
      OrderValidation.totalFor(List.generate(8, (i) => line(id: 'menu-$i'))),
      392,
    );
    expect(
      () => OrderValidation.totalFor(
        List.generate(9, (i) => line(id: 'menu-$i')),
      ),
      invalid,
    );
  });

  test('rejects non-finite, free, negative or fractional-satang prices', () {
    for (final price in [double.nan, double.infinity, -1, 0, 1.001, 100001]) {
      expect(() => OrderValidation.totalFor([line(price: price)]), invalid);
    }
  });

  test(
    'checkout rejects a removed, sold-out, foreign or repriced menu item',
    () {
      Map<String, MenuItem> menu({
        String shopId = 'shop',
        bool available = true,
        num price = 49,
      }) => {
        'menu': MenuItem(
          id: 'menu',
          shopId: shopId,
          name: 'ข้าวผัด',
          price: price,
          available: available,
        ),
      };
      for (final latest in [
        <String, MenuItem>{},
        menu(available: false),
        menu(shopId: 'another-shop'),
        menu(price: 59),
      ]) {
        expect(
          () => OrderValidation.revalidateItems(
            shopId: 'shop',
            items: [line()],
            latestMenu: latest,
          ),
          invalid,
        );
      }
    },
  );

  test('receipt takes the latest name and preserves the confirmed price', () {
    final confirmed = OrderValidation.revalidateItems(
      shopId: 'shop',
      items: [line(price: 49.9, qty: 2)],
      latestMenu: {
        'menu': MenuItem(
          id: 'menu',
          shopId: 'shop',
          name: 'ข้าวผัดไข่',
          price: 49.90,
          available: true,
        ),
      },
    );
    expect(confirmed.single.name, 'ข้าวผัดไข่');
    expect(OrderValidation.totalFor(confirmed), 99.8);
  });

  test('note limit is enforced before checkout', () {
    OrderValidation.validateNote('ไม่ใส่พริก');
    OrderValidation.validateNote(List.filled(500, 'ก').join());
    expect(
      () => OrderValidation.validateNote(List.filled(501, 'ก').join()),
      invalid,
    );
  });

  test(
    'only adjacent lifecycle transitions or pending cancellation are valid',
    () {
      for (var i = 0; i < OrderStatus.flow.length - 1; i++) {
        expect(
          OrderStatus.canTransition(
            OrderStatus.flow[i],
            OrderStatus.flow[i + 1],
          ),
          isTrue,
        );
      }
      expect(
        OrderStatus.canTransition(OrderStatus.pending, OrderStatus.cancelled),
        isTrue,
      );
      for (final pair in [
        [OrderStatus.pending, OrderStatus.ready],
        [OrderStatus.accepted, OrderStatus.cancelled],
        [OrderStatus.completed, OrderStatus.pending],
        [OrderStatus.cancelled, OrderStatus.accepted],
        [OrderStatus.cooking, OrderStatus.accepted],
      ]) {
        expect(OrderStatus.canTransition(pair[0], pair[1]), isFalse);
      }
      expect(OrderStatus.next(OrderStatus.completed), isNull);
      expect(OrderStatus.next('unknown'), isNull);
    },
  );
}
