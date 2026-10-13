import '../../models/app_user.dart';
import 'package:flutter/material.dart';
import '../../models/food_order.dart';
import '../../models/shop.dart';
import '../../services/db.dart';
import '../../theme/app_theme.dart';
import '../../widgets/food_ui.dart';
import 'menu_manage_screen.dart';
import 'shop_profile_screen.dart';
import 'shop_order_history_screen.dart';
import 'shop_order_detail_screen.dart';
import 'order_actions.dart';

class OrderBoardScreen extends StatefulWidget {
  final AppUser user;
  final String shopId;
  const OrderBoardScreen({super.key, required this.user, required this.shopId});
  @override
  State<OrderBoardScreen> createState() => _OrderBoardScreenState();
}

class _OrderBoardScreenState extends State<OrderBoardScreen> {
  late Stream<Shop> _shop;
  late Stream<List<FoodOrder>> _orders;
  final _search = TextEditingController();
  final _busy = <String>{};
  String? _filter;
  bool _switching = false;
  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _connect() {
    _shop = Db().watchShop(widget.shopId);
    _orders = Db().watchShopOrders(widget.shopId);
  }

  void _openShopProfile() {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            ShopProfileScreen(shopId: widget.shopId, user: widget.user),
      ),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _action(FoodOrder order, {bool reject = false}) async {
    if (_busy.contains(order.id)) return;
    if (reject) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('ปฏิเสธออเดอร์นี้?'),
          content: const Text('ลูกค้าจะเห็นสถานะยกเลิกทันที'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('กลับ'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ยืนยันปฏิเสธ'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    if (!reject && order.status == OrderStatus.ready) {
      if (!await confirmOrderDelivery(context, order) || !mounted) return;
    }
    if (_busy.contains(order.id)) return;
    setState(() => _busy.add(order.id));
    try {
      if (reject) {
        await Db().cancelOrder(order.id);
      } else if (order.status == OrderStatus.pending) {
        final error = await Db().acceptOrder(order.id);
        if (error != null) throw OrderValidationException(error);
      } else {
        await Db().advanceStatus(order.id, order.status);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('อัปเดตไม่ได้ กรุณาตรวจสถานะล่าสุดแล้วลองอีกครั้ง'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(order.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('จัดการร้าน'),
      actions: [
        IconButton(
          tooltip: 'ประวัติและสรุปยอด',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ShopOrderHistoryScreen(shopId: widget.shopId),
            ),
          ),
          icon: const Icon(Icons.bar_chart_rounded),
        ),
        IconButton(
          tooltip: 'ข้อมูลร้านและบัญชี',
          onPressed: _openShopProfile,
          icon: const Icon(Icons.storefront_outlined),
        ),
      ],
    ),
    body: StreamBuilder<Shop>(
      stream: _shop,
      builder: (context, shopSnap) {
        if (shopSnap.hasError) {
          return StatePanel(
            title: 'โหลดร้านไม่ได้',
            message: 'ตรวจการเชื่อมต่อแล้วลองใหม่',
            action: 'ลองใหม่',
            onAction: () => setState(_connect),
          );
        }
        if (!shopSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final shop = shopSnap.data!;
        if (shop.ownerId != widget.user.uid) {
          return const StatePanel(
            title: 'เปิดร้านนี้ไม่ได้',
            message:
                'ไม่พบร้านที่บัญชีนี้เป็นเจ้าของ กรุณาตรวจบัญชีแล้วเปิดใหม่',
          );
        }
        return ContentWidth(
          child: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shop.name,
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 14),
                      Card(
                        child: SwitchListTile(
                          title: Text(
                            shop.isOpen ? 'เปิดรับออเดอร์' : 'พักรับออเดอร์',
                          ),
                          subtitle: const Text(
                            'เปลี่ยนสถานะหน้าร้านให้ลูกค้าเห็นทันที',
                          ),
                          value: shop.isOpen,
                          onChanged: _switching
                              ? null
                              : (value) async {
                                  setState(() => _switching = true);
                                  try {
                                    await Db().setShopOpen(
                                      widget.shopId,
                                      value,
                                    );
                                  } catch (error) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            error is OrderValidationException
                                                ? error.message
                                                : 'เปลี่ยนสถานะร้านไม่ได้ กรุณาลองใหม่',
                                          ),
                                          action:
                                              value &&
                                                  error
                                                      is OrderValidationException
                                              ? SnackBarAction(
                                                  label: 'แก้ข้อมูลร้าน',
                                                  onPressed: _openShopProfile,
                                                )
                                              : null,
                                        ),
                                      );
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(() => _switching = false);
                                    }
                                  }
                                },
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'ออเดอร์ที่ต้องดูแล',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          TextButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    MenuManageScreen(shopId: widget.shopId),
                              ),
                            ),
                            icon: const Icon(
                              Icons.restaurant_menu_rounded,
                              size: 18,
                            ),
                            label: const Text('จัดการเมนู'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          hintText: 'ค้นหาชื่อลูกค้าหรือเลขออเดอร์',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ChoiceChip(
                              label: const Text('ทั้งหมด'),
                              selected: _filter == null,
                              onSelected: (_) => setState(() => _filter = null),
                            ),
                            for (final status in OrderStatus.active)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: ChoiceChip(
                                  label: Text(OrderStatus.labels[status]!),
                                  selected: _filter == status,
                                  onSelected: (_) =>
                                      setState(() => _filter = status),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            body: StreamBuilder<List<FoodOrder>>(
              stream: _orders,
              builder: (context, snap) {
                if (snap.hasError) {
                  return StatePanel(
                    title: 'โหลดออเดอร์ไม่ได้',
                    message: 'ตรวจการเชื่อมต่อแล้วลองใหม่',
                    action: 'ลองใหม่',
                    onAction: () => setState(_connect),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final query = _search.text.trim().toLowerCase();
                final orders = snap.data!
                    .where(
                      (o) =>
                          (_filter == null || o.status == _filter) &&
                          (o.customerName.toLowerCase().contains(query) ||
                              o.id.toLowerCase().contains(query)),
                    )
                    .toList();
                if (orders.isEmpty) {
                  return const StatePanel(
                    icon: Icons.task_alt_rounded,
                    title: 'ไม่มีออเดอร์ในรายการนี้',
                    message: 'ออเดอร์ใหม่จะเข้ามาที่นี่เมื่อมีลูกค้าสั่ง',
                  );
                }
                return ListView.separated(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  itemCount: orders.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 16),
                  itemBuilder: (context, i) {
                    final order = orders[i];
                    final working = _busy.contains(order.id);
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    order.customerName,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                ),
                                Text(
                                  money(order.total),
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '#${order.id.substring(order.id.length > 8 ? order.id.length - 8 : 0).toUpperCase()}',
                              style: const TextStyle(
                                color: AppTheme.muted,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 12),
                            StatusPill(
                              OrderStatus.labels[order.status] ?? order.status,
                            ),
                            const Divider(),
                            for (final item in order.items)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  '${item.qty} × ${item.name}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            if (order.note.isNotEmpty)
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(top: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFEEE7),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text('หมายเหตุ: ${order.note}'),
                              ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                FilledButton(
                                  onPressed: working
                                      ? null
                                      : () => _action(order),
                                  child: Text(
                                    working
                                        ? 'กำลังอัปเดต…'
                                        : OrderStatus.actionLabel(
                                                order.status,
                                              ) ??
                                              'ถัดไป',
                                  ),
                                ),
                                if (order.status == OrderStatus.pending)
                                  TextButton(
                                    onPressed: working
                                        ? null
                                        : () => _action(order, reject: true),
                                    child: const Text('ปฏิเสธ'),
                                  ),
                                TextButton(
                                  onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ShopOrderDetailScreen(
                                        orderId: order.id,
                                      ),
                                    ),
                                  ),
                                  child: const Text('รายละเอียด'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    ),
  );
}
