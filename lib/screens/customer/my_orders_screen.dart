import '../../models/app_user.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/food_order.dart';
import '../../models/shop.dart';
import '../../services/db.dart';
import '../../theme/app_theme.dart';
import '../../widgets/food_ui.dart';
import 'menu_screen.dart';
import 'order_track_screen.dart';

class MyOrdersScreen extends StatefulWidget {
  final AppUser user;
  final bool embedded;
  const MyOrdersScreen({super.key, required this.user, this.embedded = false});
  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  int _filter = 0;
  late Stream<List<FoodOrder>> _stream;
  bool _opening = false;
  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _connect() {
    _stream = Db().watchMyOrders(widget.user.uid);
  }

  Future<void> _reorder(FoodOrder order) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final Shop shop = await Db().watchShop(order.shopId).first;
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MenuScreen(
            shop: shop,
            user: widget.user,
            reorderItems: order.items,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เปิดร้านนี้ไม่ได้ กรุณาลองใหม่')),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = ContentWidth(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'มื้อของฉัน',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 6),
                const Text(
                  'ทุกออเดอร์ ติดตามได้ในที่เดียว',
                  style: TextStyle(color: AppTheme.muted),
                ),
                const SizedBox(height: 20),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('ทั้งหมด')),
                    ButtonSegment(value: 1, label: Text('กำลังทำ')),
                    ButtonSegment(value: 2, label: Text('จบแล้ว')),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (v) => setState(() => _filter = v.first),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<FoodOrder>>(
              stream: _stream,
              builder: (context, snap) {
                if (snap.hasError) {
                  return StatePanel(
                    title: 'โหลดออเดอร์ไม่ได้',
                    message: 'ตรวจการเชื่อมต่อ แล้วลองอีกครั้ง',
                    action: 'ลองใหม่',
                    onAction: () => setState(_connect),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final orders = snap.data!
                    .where(
                      (o) =>
                          _filter == 0 ||
                          (_filter == 1
                              ? OrderStatus.active.contains(o.status)
                              : !OrderStatus.active.contains(o.status)),
                    )
                    .toList();
                if (orders.isEmpty) {
                  return const StatePanel(
                    icon: Icons.receipt_long_outlined,
                    title: 'ยังไม่มีออเดอร์ในรายการนี้',
                    message:
                        'เลือกมื้ออร่อยจากหน้าค้นหาร้าน แล้วติดตามได้ที่นี่',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  itemCount: orders.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (context, i) {
                    final order = orders[i];
                    return Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OrderTrackScreen(orderId: order.id),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.storefront_outlined,
                                    color: AppTheme.orange,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      order.shopName,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  ),
                                  Text(
                                    money(order.total),
                                    style: const TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                order.items
                                    .map((item) => '${item.name} ×${item.qty}')
                                    .join(' • '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.muted,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  StatusPill(
                                    OrderStatus.labels[order.status] ??
                                        order.status,
                                    positive:
                                        order.status != OrderStatus.cancelled,
                                  ),
                                  Text(
                                    order.createdAt == null
                                        ? 'กำลังบันทึกเวลา'
                                        : DateFormat(
                                            'd MMM HH:mm',
                                            'th',
                                          ).format(order.createdAt!),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.muted,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'ดูรายละเอียด',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.muted,
                                      ),
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: _opening
                                        ? null
                                        : () => _reorder(order),
                                    icon: const Icon(
                                      Icons.replay_rounded,
                                      size: 17,
                                    ),
                                    label: const Text('สั่งอีกครั้ง'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
    return widget.embedded
        ? body
        : Scaffold(
            appBar: AppBar(title: const Text('ออเดอร์ของฉัน')),
            body: body,
          );
  }
}
