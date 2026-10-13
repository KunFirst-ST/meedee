import '../../models/food_order.dart';

/// History follows order creation; turnover follows the completed transition.
/// Completed receipts cannot advance again, so updatedAt is the delivery time.
class MerchantReport {
  final List<FoodOrder> placedOrders;
  final int completedCount;
  final num completedTotal;
  final int undatedCompletedCount;
  final int invalidTotalCount;

  const MerchantReport._({
    required this.placedOrders,
    required this.completedCount,
    required this.completedTotal,
    required this.undatedCompletedCount,
    required this.invalidTotalCount,
  });

  factory MerchantReport.calculate(
    Iterable<FoodOrder> orders, {
    required DateTime now,
    required int days,
  }) {
    if (days < 1) throw ArgumentError.value(days, 'days', 'Must be positive');
    final localNow = now.toLocal();
    final start = DateTime(
      localNow.year,
      localNow.month,
      localNow.day - days + 1,
    );
    bool inRange(DateTime? date) =>
        date != null && !date.isBefore(start) && !date.isAfter(localNow);
    final placed = <FoodOrder>[];
    var completed = 0;
    var totalSatang = 0;
    var undated = 0;
    var invalid = 0;
    for (final order in orders) {
      if (inRange(order.createdAt)) placed.add(order);
      if (order.status != OrderStatus.completed) continue;
      if (order.updatedAt == null) {
        undated++;
        continue;
      }
      if (!inRange(order.updatedAt)) continue;
      completed++;
      if (!order.total.isFinite || order.total < 0) {
        invalid++;
        continue;
      }
      totalSatang += (order.total * 100).round();
    }
    placed.sort((a, b) => b.createdAt!.compareTo(a.createdAt!));
    return MerchantReport._(
      placedOrders: List.unmodifiable(placed),
      completedCount: completed,
      completedTotal: totalSatang / 100,
      undatedCompletedCount: undated,
      invalidTotalCount: invalid,
    );
  }
}
