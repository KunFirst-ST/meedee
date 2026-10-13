import '../../models/app_user.dart';
import 'package:flutter/material.dart';
import '../../models/food_order.dart';
import '../../models/menu_item.dart';
import '../../models/shop.dart';
import '../../services/cart_store.dart';
import '../../services/db.dart';
import '../../theme/app_theme.dart';
import '../../widgets/food_ui.dart';
import 'order_track_screen.dart';

class CheckoutScreen extends StatefulWidget {
  final Shop shop;
  final AppUser user;
  final CartDraft draft;
  final Db? database;
  const CheckoutScreen({
    super.key,
    required this.shop,
    required this.user,
    required this.draft,
    this.database,
  });
  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  late final Db _db = widget.database ?? Db();
  late final TextEditingController _note;
  late Stream<Shop> _shop;
  late Stream<List<MenuItem>> _menu;
  bool _placing = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _note = TextEditingController(text: widget.draft.note);
    _connect();
  }

  void _connect() {
    _shop = _db.watchShop(widget.shop.id);
    _menu = _db.watchMenu(widget.shop.id);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _place(Shop shop, List<MenuItem> menu) async {
    if (_placing) return;
    final items = menu
        .where((m) => widget.draft.quantity(m.id) > 0)
        .map(
          (m) => OrderItem(
            menuItemId: m.id,
            name: m.name,
            price: m.price,
            qty: widget.draft.quantity(m.id),
          ),
        )
        .toList();
    if (items.isEmpty) return;
    setState(() {
      _placing = true;
      _error = null;
    });
    try {
      final id = await _db.placeOrder(
        shop: shop,
        customerId: widget.user.uid,
        customerName: widget.user.displayName ?? 'ลูกค้า',
        items: items,
        note: _note.text,
        requestId: widget.draft.requestId,
      );
      // MenuScreen still owns this registered draft when tracking replaces checkout.
      // Clear its contents in place so the next visit observes the same cart.
      widget.draft.clear();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => OrderTrackScreen(orderId: id, database: _db),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _placing = false;
          _error = error is OrderValidationException
              ? error.message
              : 'ยืนยันออเดอร์ไม่ได้ กรุณาตรวจการเชื่อมต่อแล้วลองอีกครั้ง';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_placing,
    child: Scaffold(
      appBar: AppBar(title: const Text('ตรวจรายการสั่งซื้อ')),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<Shop>(
              stream: _shop,
              builder: (context, shopSnap) => StreamBuilder<List<MenuItem>>(
                stream: _menu,
                builder: (context, menuSnap) {
                  if (shopSnap.hasError || menuSnap.hasError) {
                    return StatePanel(
                      icon: Icons.wifi_off_rounded,
                      title: 'ตรวจรายการไม่ได้',
                      message: 'ตรวจการเชื่อมต่อ แล้วลองอีกครั้ง',
                      action: 'ลองใหม่',
                      onAction: () => setState(_connect),
                    );
                  }
                  if (!shopSnap.hasData || !menuSnap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final shop = shopSnap.data!;
                  final menu = menuSnap.data!;
                  return AnimatedBuilder(
                    animation: widget.draft,
                    builder: (context, _) {
                      final ids = widget.draft.quantities.keys.toList();
                      final selected = menu
                          .where((m) => widget.draft.quantity(m.id) > 0)
                          .toList();
                      final missing = ids
                          .where((id) => !menu.any((m) => m.id == id))
                          .toList();
                      final unavailable = selected
                          .where((m) => !m.available)
                          .toList();
                      final total = selected.fold<num>(
                        0,
                        (sum, m) => sum + m.price * widget.draft.quantity(m.id),
                      );
                      final canOrder =
                          shop.isOpen &&
                          selected.isNotEmpty &&
                          missing.isEmpty &&
                          unavailable.isEmpty &&
                          ids.length <= 8;
                      return Column(
                        children: [
                          Expanded(
                            child: ContentWidth(
                              child: ListView(
                                padding: const EdgeInsets.all(24),
                                children: [
                                  Text(
                                    'อีกนิดเดียว ก็ได้มื้ออร่อย',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineSmall,
                                  ),
                                  const SizedBox(height: 18),
                                  Card(
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.all(18),
                                      leading: const CircleAvatar(
                                        backgroundColor: Color(0xFFFFEEE7),
                                        child: Icon(
                                          Icons.storefront_outlined,
                                          color: AppTheme.orange,
                                        ),
                                      ),
                                      title: Text(
                                        shop.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      subtitle: Text(
                                        'รับที่ร้าน${shop.location == null ? '' : ' • ${shop.location}'}',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'รายการอาหาร',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleLarge,
                                        ),
                                      ),
                                      Text(
                                        '${widget.draft.count} รายการ',
                                        style: const TextStyle(
                                          color: AppTheme.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  for (final item in selected)
                                    Card(
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    item.name,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                                Text(
                                                  money(
                                                    item.price *
                                                        widget.draft.quantity(
                                                          item.id,
                                                        ),
                                                  ),
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    '${money(item.price)} / ที่',
                                                    style: const TextStyle(
                                                      color: AppTheme.muted,
                                                    ),
                                                  ),
                                                ),
                                                IconButton(
                                                  tooltip: 'ลด ${item.name}',
                                                  onPressed: _placing
                                                      ? null
                                                      : () => widget.draft
                                                            .setQuantity(
                                                              item.id,
                                                              widget.draft
                                                                      .quantity(
                                                                        item.id,
                                                                      ) -
                                                                  1,
                                                            ),
                                                  icon: const Icon(
                                                    Icons
                                                        .remove_circle_outline_rounded,
                                                  ),
                                                ),
                                                Text(
                                                  '${widget.draft.quantity(item.id)}',
                                                ),
                                                IconButton(
                                                  tooltip: 'เพิ่ม ${item.name}',
                                                  onPressed:
                                                      _placing ||
                                                          !item.available ||
                                                          widget.draft.quantity(
                                                                item.id,
                                                              ) >=
                                                              20
                                                      ? null
                                                      : () => widget.draft
                                                            .setQuantity(
                                                              item.id,
                                                              widget.draft
                                                                      .quantity(
                                                                        item.id,
                                                                      ) +
                                                                  1,
                                                            ),
                                                  icon: const Icon(
                                                    Icons
                                                        .add_circle_outline_rounded,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (!item.available)
                                              const Text(
                                                'เมนูหมดแล้ว กรุณานำออกจากรายการ',
                                                style: TextStyle(
                                                  color: Colors.red,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  for (final id in missing)
                                    ListTile(
                                      title: const Text(
                                        'เมนูนี้ถูกนำออกจากร้านแล้ว',
                                      ),
                                      trailing: TextButton(
                                        onPressed: _placing
                                            ? null
                                            : () => widget.draft.setQuantity(
                                                id,
                                                0,
                                              ),
                                        child: const Text('นำออก'),
                                      ),
                                    ),
                                  const SizedBox(height: 20),
                                  TextField(
                                    controller: _note,
                                    enabled: !_placing,
                                    maxLength: 500,
                                    maxLines: 3,
                                    onChanged: (value) =>
                                        widget.draft.note = value,
                                    decoration: const InputDecoration(
                                      labelText: 'หมายเหตุถึงร้าน',
                                      hintText:
                                          'เช่น ไม่เผ็ด ไม่ใส่ต้นหอม หรือข้อมูลการแพ้อาหาร',
                                      alignLabelWithHint: true,
                                    ),
                                  ),
                                  const Text(
                                    'หากแพ้อาหาร ควรยืนยันกับร้านก่อนสั่งซื้อ',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.muted,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Card(
                                    color: const Color(0xFFE7F5EE),
                                    child: const Padding(
                                      padding: EdgeInsets.all(18),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.payments_outlined,
                                            color: AppTheme.green,
                                          ),
                                          SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'ชำระเงินที่ร้าน',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                SizedBox(height: 4),
                                                Text(
                                                  'ยืนยันกับร้านเมื่อไปรับอาหาร',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: AppTheme.muted,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  Row(
                                    children: [
                                      const Expanded(child: Text('ค่าอาหาร')),
                                      Text(money(total)),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  const Row(
                                    children: [
                                      Expanded(child: Text('ค่าบริการในแอป')),
                                      Text('฿0'),
                                    ],
                                  ),
                                  const Divider(),
                                  Row(
                                    children: [
                                      Text(
                                        'ยอดรวม',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleLarge,
                                      ),
                                      const Spacer(),
                                      Text(
                                        money(total),
                                        style: const TextStyle(
                                          fontSize: 26,
                                          fontWeight: FontWeight.w800,
                                          color: AppTheme.orange,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  const Text(
                                    'ใช้ราคาปัจจุบันที่แสดงในรายการ • รับอาหารที่ร้าน',
                                    style: TextStyle(
                                      color: AppTheme.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (!shop.isOpen)
                                    const Padding(
                                      padding: EdgeInsets.only(top: 16),
                                      child: Text(
                                        'ร้านปิดแล้ว กรุณากลับมาสั่งเมื่อร้านเปิด',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ),
                                  if (_error != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 16),
                                      child: Text(
                                        _error!,
                                        style: const TextStyle(
                                          color: Colors.red,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          SafeArea(
                            top: false,
                            child: Container(
                              color: Colors.white,
                              padding: const EdgeInsets.all(20),
                              child: ContentWidth(
                                child: SizedBox(
                                  width: double.infinity,
                                  child: FilledButton(
                                    onPressed: !canOrder || _placing
                                        ? null
                                        : () => _place(shop, menu),
                                    child: _placing
                                        ? const SizedBox(
                                            height: 22,
                                            width: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : Text(
                                            'ยืนยันสั่งซื้อ • ${money(total)}',
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
