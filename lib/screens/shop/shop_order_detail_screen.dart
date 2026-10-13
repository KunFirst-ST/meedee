import 'package:flutter/material.dart';
import '../../models/food_order.dart';
import '../../services/db.dart';
import '../../widgets/food_ui.dart';
import 'order_actions.dart';

class ShopOrderDetailScreen extends StatefulWidget {
  final String orderId;
  const ShopOrderDetailScreen({super.key, required this.orderId});
  @override
  State<ShopOrderDetailScreen> createState() => _ShopOrderDetailScreenState();
}

class _ShopOrderDetailScreenState extends State<ShopOrderDetailScreen> {
  late Stream<FoodOrder> _stream = Db().watchOrder(widget.orderId);
  bool _busy = false;
  Future<void> _advance(FoodOrder order) async {
    if (_busy) return;
    if (order.status == OrderStatus.ready) {
      if (!await confirmOrderDelivery(context, order) || !mounted) return;
      if (_busy) return;
    }
    setState(() => _busy = true);
    try {
      if (order.status == OrderStatus.pending) {
        final error = await Db().acceptOrder(order.id);
        if (error != null) throw OrderValidationException(error);
      } else {
        await Db().advanceStatus(order.id, order.status);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('อัปเดตไม่ได้ ตรวจสถานะล่าสุดแล้วลองอีกครั้ง'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('รายละเอียดออเดอร์')),
    body: StreamBuilder<FoodOrder>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return StatePanel(
            title: 'โหลดออเดอร์ไม่ได้',
            message: snap.error is OrderValidationException
                ? (snap.error! as OrderValidationException).message
                : 'ตรวจการเชื่อมต่อแล้วลองอีกครั้ง',
            action: 'ลองใหม่',
            onAction: () =>
                setState(() => _stream = Db().watchOrder(widget.orderId)),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final order = snap.data!;
        if (order.shopId.isEmpty ||
            order.customerId.isEmpty ||
            order.items.isEmpty) {
          return const StatePanel(
            title: 'ไม่พบออเดอร์นี้',
            message: 'กลับไปตรวจรายการล่าสุดของร้าน',
          );
        }
        return ContentWidth(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                order.customerName,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              SelectableText('เลขออเดอร์: ${order.id}'),
              const SizedBox(height: 16),
              StatusPill(
                OrderStatus.labels[order.status] ?? order.status,
                positive: order.status != OrderStatus.cancelled,
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      for (final item in order.items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text('${item.qty} × ${item.name}'),
                              ),
                              Text(money(item.subtotal)),
                            ],
                          ),
                        ),
                      const Divider(),
                      Row(
                        children: [
                          const Expanded(child: Text('ยอดรวม')),
                          Text(
                            money(order.total),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (order.note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Text('หมายเหตุ: ${order.note}'),
                ),
              const SizedBox(height: 24),
              if (OrderStatus.next(order.status) != null)
                FilledButton(
                  onPressed: _busy ? null : () => _advance(order),
                  child: Text(
                    _busy
                        ? 'กำลังอัปเดต…'
                        : OrderStatus.actionLabel(order.status) ?? 'อัปเดต',
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}
