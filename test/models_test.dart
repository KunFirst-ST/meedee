import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:msu_food2/models/food_order.dart';
import 'package:msu_food2/models/menu_item.dart';
import 'package:msu_food2/models/shop.dart';

void main() {
  test(
    'old order receipts remain readable without menu IDs or photographs',
    () {
      final item = OrderItem.fromMap({'name': 'ผัดไทย', 'price': 59, 'qty': 2});
      expect(item.menuItemId, isNull);
      expect(item.imageBytes, isNull);
      expect(item.subtotal, 118);
    },
  );

  test('order receipt preserves menu identity and optional image', () {
    final item = OrderItem(
      menuItemId: 'pad-thai',
      name: 'ผัดไทย',
      price: 59.50,
      qty: 3,
      imageBytes: Uint8List.fromList([1, 2, 3]),
    );
    final restored = OrderItem.fromMap(item.toMap());
    expect(restored.menuItemId, 'pad-thai');
    expect(restored.subtotal, 178.5);
    expect(restored.imageBytes, [1, 2, 3]);
  });

  test('unknown shop details remain unset instead of inventing metrics', () {
    final shop = Shop.fromMap('shop', {
      'name': 'ครัว MSU',
      'ownerId': 'owner',
      'isOpen': false,
    });
    expect(shop.isOpen, isFalse);
    expect(shop.description, isNull);
    expect(shop.category, isNull);
    expect(shop.location, isNull);
    expect(shop.preparationMinutes, isNull);
    expect(shop.ratingAverage, isNull);
    expect(shop.reviewCount, 0);
    expect(() => Shop.fromMap('deleted', {}), throwsFormatException);
  });

  test(
    'shop details retain real values and reject invalid preparation time',
    () {
      final shop = Shop.fromMap('shop', {
        'name': 'ครัว MSU',
        'ownerId': 'owner',
        'isOpen': true,
        'description': ' อาหารตามสั่ง ',
        'category': 'อาหารไทย',
        'location': 'หน้ามหาวิทยาลัย',
        'preparationMinutes': 15,
      });
      expect(shop.description, 'อาหารตามสั่ง');
      expect(shop.preparationMinutes, 15);
      expect(
        Shop.fromMap('shop', {
          'name': 'ครัว MSU',
          'ownerId': 'owner',
          'isOpen': false,
          'preparationMinutes': -1,
        }).preparationMinutes,
        isNull,
      );
    },
  );

  test('shop ratings and a completed order review parse from API data', () {
    final shop = Shop.fromMap('shop', {
      'name': 'ครัว MSU',
      'ownerId': 'owner',
      'isOpen': true,
      'ratingAverage': 4.5,
      'reviewCount': 12,
    });
    expect(shop.ratingAverage, 4.5);
    expect(shop.reviewCount, 12);

    final order = FoodOrder.fromMap('receipt', {
      'items': [],
      'shopId': 'shop',
      'customerId': 'customer',
      'status': OrderStatus.completed,
      'total': 0,
      'review': {'rating': 4, 'comment': 'ดีมาก'},
    });
    expect(order.review?.rating, 4);
    expect(order.review?.comment, 'ดีมาก');
  });

  test(
    'menu preserves unavailable status, handles broken images and rejects missing status',
    () {
      final item = MenuItem.fromMap('menu', {
        'shopId': 'shop',
        'name': 'ข้าวผัด',
        'price': 49,
        'available': false,
        'imageBase64': '%%%invalid%%%',
        'category': ' จานเดียว ',
      });
      expect(item.available, isFalse);
      expect(item.imageBytes, isNull);
      expect(item.shopId, 'shop');
      expect(item.category, 'จานเดียว');
      expect(
        () => MenuItem.fromMap('menu', {
          'shopId': 'shop',
          'name': 'ข้าวผัด',
          'price': 49,
        }),
        throwsFormatException,
      );
    },
  );

  test('order model preserves both server timestamps', () {
    final created = DateTime.utc(2026, 10, 12, 10);
    final updated = created.add(const Duration(minutes: 2));
    final order = FoodOrder.fromMap('receipt', {
      'items': [
        {'menuItemId': 'menu', 'name': 'ข้าวผัด', 'price': 49, 'qty': 1},
      ],
      'shopId': 'shop',
      'customerId': 'customer',
      'status': OrderStatus.pending,
      'total': 49,
      'createdAt': created.toIso8601String(),
      'updatedAt': updated.toIso8601String(),
    });
    expect(order.id, 'receipt');
    expect(order.items.single.menuItemId, 'menu');
    expect(order.createdAt!.isAtSameMomentAs(created), isTrue);
    expect(order.updatedAt!.isAtSameMomentAs(updated), isTrue);
  });
}
