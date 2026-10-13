import 'package:flutter_test/flutter_test.dart';
import 'package:msu_food2/models/shop.dart';
import 'package:msu_food2/services/db.dart';

Shop shop({String? location, int? minutes}) => Shop(
  id: 'shop-owner',
  name: 'ร้านของเจ้าของ',
  ownerId: 'owner',
  isOpen: false,
  location: location,
  preparationMinutes: minutes,
);

void main() {
  test('opening needs an actual pickup location and preparation time', () {
    for (final location in [null, '', '   ']) {
      expect(
        () => ShopReadiness.requireReady(shop(location: location, minutes: 15)),
        throwsA(isA<OrderValidationException>()),
      );
    }
    for (final minutes in [null, 0, 241]) {
      expect(
        () => ShopReadiness.requireReady(
          shop(location: 'อาคาร B ชั้น 1', minutes: minutes),
        ),
        throwsA(isA<OrderValidationException>()),
      );
    }
  });
  test(
    'valid preparation boundaries preserve owner-entered pickup information',
    () {
      for (final minutes in [1, 15, 240]) {
        final value = shop(location: 'อาคาร B ชั้น 1', minutes: minutes);
        expect(() => ShopReadiness.requireReady(value), returnsNormally);
        expect(value.location, 'อาคาร B ชั้น 1');
        expect(value.isOpen, isFalse);
      }
    },
  );
}
