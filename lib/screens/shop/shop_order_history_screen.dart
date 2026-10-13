import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/food_order.dart';
import '../../services/db.dart';
import '../../theme/app_theme.dart';
import '../../widgets/food_ui.dart';
import 'merchant_report.dart';
import 'shop_order_detail_screen.dart';

class ShopOrderHistoryScreen extends StatefulWidget {
  final String shopId;
  const ShopOrderHistoryScreen({super.key, required this.shopId});
  @override
  State<ShopOrderHistoryScreen> createState() => _ShopOrderHistoryScreenState();
}

class _ShopOrderHistoryScreenState extends State<ShopOrderHistoryScreen>
    with WidgetsBindingObserver {
  int _range = 0;
  late Stream<List<FoodOrder>> _stream;
  Timer? _rollover;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _stream = Db().watchShopOrderHistory(widget.shopId);
    _scheduleRollover();
  }

  void _scheduleRollover() {
    _rollover?.cancel();
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    _rollover = Timer(tomorrow.difference(now), () {
      if (!mounted) return;
      setState(() {});
      _scheduleRollover();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {});
      _scheduleRollover();
    }
  }

  @override
  void dispose() {
    _rollover?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ประวัติและสรุปยอด')),
    body: StreamBuilder<List<FoodOrder>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return StatePanel(
            title: 'โหลดประวัติไม่ได้',
            message: 'ตรวจการเชื่อมต่อแล้วลองใหม่',
            action: 'ลองใหม่',
            onAction: () => setState(
              () => _stream = Db().watchShopOrderHistory(widget.shopId),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final report = MerchantReport.calculate(
          snap.data!,
          now: DateTime.now(),
          days: const [1, 7, 30][_range],
        );
        final orders = report.placedOrders;
        return ContentWidth(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SegmentedButton<int>(
                          segments: const [
                            ButtonSegment(value: 0, label: Text('วันนี้')),
                            ButtonSegment(value: 1, label: Text('7 วัน')),
                            ButtonSegment(value: 2, label: Text('30 วัน')),
                          ],
                          selected: {_range},
                          onSelectionChanged: (v) =>
                              setState(() => _range = v.first),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Wrap(
                            spacing: 28,
                            runSpacing: 20,
                            children: [
                              _summary(
                                'ส่งมอบแล้ว',
                                '${report.completedCount} ออเดอร์',
                              ),
                              _summary(
                                'ยอดอาหารที่ส่งมอบ',
                                money(report.completedTotal),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'ยอดนับตามวันที่ร้านยืนยันส่งมอบ ไม่รวมออเดอร์ค้างหรือยกเลิก',
                        style: TextStyle(fontSize: 12, color: AppTheme.muted),
                      ),
                      if (report.undatedCompletedCount > 0) ...[
                        const SizedBox(height: 8),
                        Text(
                          'มี ${report.undatedCompletedCount} ออเดอร์ที่ไม่มีเวลาส่งมอบ ไม่รวมในยอดช่วงเวลา',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.muted,
                          ),
                        ),
                      ],
                      if (report.invalidTotalCount > 0) ...[
                        const SizedBox(height: 8),
                        Text(
                          'ยอดของ ${report.invalidTotalCount} ออเดอร์ไม่ถูกต้อง จึงยังไม่รวมในยอดเงิน',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.muted,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Text(
                        'รายการตามวันที่สั่ง',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
              ),
              if (orders.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: StatePanel(
                    icon: Icons.history_rounded,
                    title: 'ยังไม่มีรายการสั่งในช่วงนี้',
                    message: 'เลือกช่วงเวลาอื่นเพื่อดูออเดอร์',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  sliver: SliverList.builder(
                    itemCount: orders.length,
                    itemBuilder: (context, i) {
                      final order = orders[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(18),
                            leading: const Icon(Icons.receipt_long_outlined),
                            title: Text(order.customerName),
                            subtitle: Text(
                              '${OrderStatus.labels[order.status] ?? order.status}\n'
                              '${DateFormat('d MMM HH:mm', 'th').format(order.createdAt!)}\n'
                              '${money(order.total)}',
                            ),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    ShopOrderDetailScreen(orderId: order.id),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );

  Widget _summary(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: AppTheme.muted)),
      const SizedBox(height: 6),
      Text(value, style: Theme.of(context).textTheme.titleLarge),
    ],
  );
}
