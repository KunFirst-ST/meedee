import 'package:flutter_test/flutter_test.dart';
import 'package:msu_food2/models/food_order.dart';
import 'package:msu_food2/screens/shop/merchant_report.dart';

FoodOrder _order(
  String id, {
  required DateTime? placed,
  required DateTime? updated,
  String status = OrderStatus.completed,
  num total = 55,
}) => FoodOrder(
  id: id,
  shopId: 'owned-shop',
  shopName: 'ร้านของฉัน',
  customerId: 'customer',
  customerName: 'ลูกค้า',
  items: [OrderItem(menuItemId: 'rice', name: 'ข้าว', price: 55, qty: 1)],
  total: total,
  status: status,
  note: '',
  createdAt: placed,
  updatedAt: updated,
);

void main() {
  final now = DateTime(2026, 10, 13, 14);
  test('today turnover includes yesterday orders delivered today', () {
    final report = MerchantReport.calculate(
      [
        _order(
          'yesterday',
          placed: DateTime(2026, 10, 12, 23),
          updated: DateTime(2026, 10, 13, 9),
        ),
        _order(
          'old-delivery',
          placed: DateTime(2026, 10, 12, 20),
          updated: DateTime(2026, 10, 12, 22),
        ),
        _order(
          'today-pending',
          placed: DateTime(2026, 10, 13, 11),
          updated: DateTime(2026, 10, 13, 11),
          status: OrderStatus.pending,
        ),
      ],
      now: now,
      days: 1,
    );
    expect(report.completedCount, 1);
    expect(report.completedTotal, 55);
    expect(report.placedOrders.map((order) => order.id), ['today-pending']);
  });
  test(
    'seven calendar days includes the full first day and excludes older dates',
    () {
      final report = MerchantReport.calculate(
        [
          _order(
            'included-midnight',
            placed: DateTime(2026, 10, 7),
            updated: DateTime(2026, 10, 7),
          ),
          _order(
            'too-old',
            placed: DateTime(2026, 10, 6, 23, 59),
            updated: DateTime(2026, 10, 6, 23, 59),
          ),
          _order(
            'future',
            placed: DateTime(2026, 10, 13, 15),
            updated: DateTime(2026, 10, 13, 15),
          ),
        ],
        now: now,
        days: 7,
      );
      expect(report.placedOrders.map((order) => order.id), [
        'included-midnight',
      ]);
      expect(report.completedCount, 1);
    },
  );
  test(
    'only completed receipts affect turnover and satang totals stay exact',
    () {
      final report = MerchantReport.calculate(
        [
          _order('one', placed: now, updated: now, total: .1),
          _order('two', placed: now, updated: now, total: .2),
          _order(
            'cancelled',
            placed: now,
            updated: now,
            total: 1000,
            status: OrderStatus.cancelled,
          ),
          _order(
            'ready',
            placed: now,
            updated: now,
            total: 1000,
            status: OrderStatus.ready,
          ),
        ],
        now: now,
        days: 1,
      );
      expect(report.completedCount, 2);
      expect(report.completedTotal, .3);
      expect(report.placedOrders, hasLength(4));
    },
  );
  test('missing delivery timestamps never become invented turnover dates', () {
    final report = MerchantReport.calculate(
      [
        _order('legacy', placed: now, updated: null),
        _order('invalid-total', placed: now, updated: now, total: double.nan),
      ],
      now: now,
      days: 30,
    );
    expect(report.undatedCompletedCount, 1);
    expect(report.invalidTotalCount, 1);
    expect(report.completedCount, 1);
    expect(report.completedTotal, 0);
  });
  test(
    'sorting history preserves the source receipts and returned list is immutable',
    () {
      final receipts = [
        _order(
          'older',
          placed: DateTime(2026, 10, 12),
          updated: DateTime(2026, 10, 12),
        ),
        _order('newer', placed: now, updated: now),
      ];
      final report = MerchantReport.calculate(receipts, now: now, days: 7);
      expect(receipts.first.id, 'older');
      expect(report.placedOrders.first.id, 'newer');
      expect(() => report.placedOrders.clear(), throwsUnsupportedError);
    },
  );
  test('range start follows calendar dates across month boundaries', () {
    final report = MerchantReport.calculate(
      [
        _order(
          'included',
          placed: DateTime(2026, 9, 28),
          updated: DateTime(2026, 9, 28),
        ),
        _order(
          'excluded',
          placed: DateTime(2026, 9, 27, 23, 59),
          updated: DateTime(2026, 9, 27, 23, 59),
        ),
      ],
      now: DateTime(2026, 10, 4, 12),
      days: 7,
    );
    expect(report.completedCount, 1);
    expect(
      () => MerchantReport.calculate([], now: now, days: 0),
      throwsArgumentError,
    );
  });
}
