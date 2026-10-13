import '../../models/app_user.dart';
import 'package:flutter/material.dart';
import '../../models/food_order.dart';
import '../../models/menu_item.dart';
import '../../models/shop.dart';
import '../../services/cart_store.dart';
import '../../services/db.dart';
import '../../theme/app_theme.dart';
import '../../widgets/food_ui.dart';
import '../../widgets/menu_image.dart';
import 'checkout_screen.dart';
import 'shop_reviews_screen.dart';

class MenuScreen extends StatefulWidget {
  final Shop shop;
  final AppUser user;
  final List<OrderItem>? reorderItems;
  const MenuScreen({
    super.key,
    required this.shop,
    required this.user,
    this.reorderItems,
  });
  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  late Stream<Shop> _shopStream;
  late Stream<List<MenuItem>> _menuStream;
  late CartDraft _draft;
  final _search = TextEditingController();
  int? _budget;
  bool _reorderLoaded = false;
  @override
  void initState() {
    super.initState();
    _draft = CartStore.forShop(widget.user.uid, widget.shop.id);
    _connect();
  }

  void _connect() {
    _shopStream = Db().watchShop(widget.shop.id);
    _menuStream = Db().watchMenu(widget.shop.id);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _add(MenuItem item) {
    if (_draft.quantity(item.id) == 0 && _draft.quantities.length >= 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เลือกได้สูงสุด 8 เมนูต่อออเดอร์')),
      );
      return;
    }
    _draft.setQuantity(item.id, _draft.quantity(item.id) + 1);
  }

  void _loadReorder(List<MenuItem> menu) {
    if (_reorderLoaded || widget.reorderItems == null) return;
    _reorderLoaded = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _draft.clear();
      var skipped = 0;
      for (final old in widget.reorderItems!) {
        final matches = menu.where(
          (m) => m.available && m.id == old.menuItemId,
        );
        if (matches.isEmpty || _draft.quantities.length >= 8) {
          skipped++;
          continue;
        }
        _draft.setQuantity(matches.first.id, old.qty.clamp(1, 20));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            skipped > 0
                ? 'เพิ่มรายการที่ยังมีขายแล้ว มี $skipped เมนูที่เพิ่มไม่ได้ • ใช้ราคาปัจจุบัน'
                : 'เพิ่มรายการเดิมแล้ว กรุณาตรวจราคาปัจจุบันก่อนสั่ง',
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('เลือกมื้ออร่อย')),
    body: Column(
      children: [
        Expanded(
          child: StreamBuilder<Shop>(
            stream: _shopStream,
            builder: (context, shopSnap) {
              if (shopSnap.hasError) {
                return StatePanel(
                  icon: Icons.wifi_off_rounded,
                  title: 'เชื่อมต่อร้านไม่ได้',
                  message: 'ลองใหม่ก่อนเพิ่มอาหารลงตะกร้า',
                  action: 'ลองใหม่',
                  onAction: () => setState(_connect),
                );
              }
              if (!shopSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final shop = shopSnap.data!;
              return StreamBuilder<List<MenuItem>>(
                stream: _menuStream,
                builder: (context, menuSnap) {
                  if (menuSnap.hasError) {
                    return StatePanel(
                      title: 'โหลดเมนูไม่ได้',
                      message: 'ตรวจการเชื่อมต่อ แล้วลองใหม่',
                      action: 'ลองใหม่',
                      onAction: () => setState(_connect),
                    );
                  }
                  if (!menuSnap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final menu = menuSnap.data!;
                  _loadReorder(menu);
                  final query = _search.text.trim().toLowerCase();
                  final visible = menu
                      .where(
                        (m) =>
                            m.name.toLowerCase().contains(query) &&
                            (_budget == null || m.price <= _budget!),
                      )
                      .toList();
                  return AnimatedBuilder(
                    animation: _draft,
                    builder: (context, _) {
                      final total = menu.fold<num>(
                        0,
                        (sum, m) => sum + m.price * _draft.quantity(m.id),
                      );
                      return Column(
                        children: [
                          Expanded(
                            child: ContentWidth(
                              child: ListView(
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  12,
                                  24,
                                  24,
                                ),
                                children: [
                                  const SizedBox(height: 20),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          shop.name,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.headlineLarge,
                                        ),
                                      ),
                                      StatusPill(
                                        shop.isOpen ? 'เปิดอยู่' : 'ร้านปิด',
                                        positive: shop.isOpen,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.star_rounded,
                                        size: 18,
                                        color: Color(0xFFF2A900),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        shop.reviewCount == 0
                                            ? 'ยังไม่มีรีวิว'
                                            : '${shop.ratingAverage?.toStringAsFixed(1) ?? '—'} จาก ${shop.reviewCount} รีวิว',
                                        style: const TextStyle(
                                          color: AppTheme.muted,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                      onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ShopReviewsScreen(
                                            shopId: shop.id,
                                            shopName: shop.name,
                                          ),
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.rate_review_outlined,
                                      ),
                                      label: const Text('ดูรีวิวทั้งหมด'),
                                    ),
                                  ),
                                  if (shop.description != null) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      shop.description!,
                                      style: const TextStyle(
                                        color: AppTheme.muted,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 14),
                                  Wrap(
                                    spacing: 16,
                                    runSpacing: 8,
                                    children: [
                                      const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.shopping_bag_outlined,
                                            size: 17,
                                            color: AppTheme.orange,
                                          ),
                                          SizedBox(width: 5),
                                          Text('รับอาหารที่ร้าน'),
                                        ],
                                      ),
                                      if (shop.preparationMinutes != null)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.schedule_rounded,
                                              size: 17,
                                              color: AppTheme.muted,
                                            ),
                                            const SizedBox(width: 5),
                                            Text(
                                              'ประมาณ ${shop.preparationMinutes} นาที',
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                  if (shop.location != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 10),
                                      child: Text(
                                        shop.location!,
                                        style: const TextStyle(
                                          color: AppTheme.muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  if (!shop.isOpen)
                                    const Padding(
                                      padding: EdgeInsets.only(top: 16),
                                      child: Text(
                                        'ร้านปิดอยู่ ดูเมนูได้ และกลับมาสั่งเมื่อร้านเปิด',
                                        style: TextStyle(color: AppTheme.muted),
                                      ),
                                    ),
                                  const Divider(height: 36),
                                  TextField(
                                    controller: _search,
                                    onChanged: (_) => setState(() {}),
                                    decoration: const InputDecoration(
                                      prefixIcon: Icon(Icons.search_rounded),
                                      hintText: 'ค้นหาเมนูที่อยากกิน',
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: [
                                        for (final budget in <int?>[
                                          null,
                                          50,
                                          80,
                                        ])
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              right: 8,
                                            ),
                                            child: ChoiceChip(
                                              label: Text(
                                                budget == null
                                                    ? 'ทุกงบ'
                                                    : 'ไม่เกิน ฿$budget',
                                              ),
                                              selected: _budget == budget,
                                              onSelected: (_) => setState(
                                                () => _budget = budget,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'เมนูอาหาร',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleLarge,
                                        ),
                                      ),
                                      Text(
                                        '${visible.length} เมนู',
                                        style: const TextStyle(
                                          color: AppTheme.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  if (visible.isEmpty)
                                    StatePanel(
                                      title: menu.isEmpty
                                          ? 'ร้านยังไม่เพิ่มเมนู'
                                          : 'ไม่พบเมนูในงบนี้',
                                      message:
                                          'ลองเปลี่ยนคำค้นหาหรือเลือกทุกงบ',
                                    ),
                                  for (final item in visible)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: Card(
                                        child: Padding(
                                          padding: const EdgeInsets.all(14),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                child: MenuImage(
                                                  bytes: item.imageBytes,
                                                  size: 84,
                                                  grayscale: !item.available,
                                                ),
                                              ),
                                              const SizedBox(width: 14),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      item.name,
                                                      style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                    if (item.description !=
                                                        null) ...[
                                                      const SizedBox(height: 5),
                                                      Text(
                                                        item.description!,
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          color: AppTheme.muted,
                                                        ),
                                                      ),
                                                    ],
                                                    const SizedBox(height: 12),
                                                    Wrap(
                                                      crossAxisAlignment:
                                                          WrapCrossAlignment
                                                              .center,
                                                      spacing: 8,
                                                      children: [
                                                        Text(
                                                          money(item.price),
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 17,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800,
                                                              ),
                                                        ),
                                                        if (!item.available)
                                                          const StatusPill(
                                                            'หมดชั่วคราว',
                                                            positive: false,
                                                          ),
                                                      ],
                                                    ),
                                                    Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment.end,
                                                      children: [
                                                        if (_draft.quantity(
                                                              item.id,
                                                            ) >
                                                            0) ...[
                                                          IconButton(
                                                            tooltip:
                                                                'ลด ${item.name}',
                                                            onPressed: () =>
                                                                _draft.setQuantity(
                                                                  item.id,
                                                                  _draft.quantity(
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
                                                            '${_draft.quantity(item.id)}',
                                                            style:
                                                                const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                ),
                                                          ),
                                                        ],
                                                        IconButton.filled(
                                                          tooltip:
                                                              'เพิ่ม ${item.name}',
                                                          onPressed:
                                                              !shop.isOpen ||
                                                                  !item
                                                                      .available ||
                                                                  _draft.quantity(
                                                                        item.id,
                                                                      ) >=
                                                                      20
                                                              ? null
                                                              : () =>
                                                                    _add(item),
                                                          icon: const Icon(
                                                            Icons.add_rounded,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          if (_draft.count > 0)
                            SafeArea(
                              top: false,
                              child: Container(
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  12,
                                  24,
                                  12,
                                ),
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  border: Border(
                                    top: BorderSide(color: AppTheme.line),
                                  ),
                                ),
                                child: ContentWidth(
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: FilledButton(
                                      onPressed: shop.isOpen
                                          ? () => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => CheckoutScreen(
                                                  shop: shop,
                                                  user: widget.user,
                                                  draft: _draft,
                                                ),
                                              ),
                                            )
                                          : null,
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(
                                                alpha: .2,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text('${_draft.count}'),
                                          ),
                                          const SizedBox(width: 12),
                                          const Expanded(
                                            child: Text('ดูตะกร้า'),
                                          ),
                                          Text(money(total)),
                                          const SizedBox(width: 8),
                                          const Icon(
                                            Icons.arrow_forward_rounded,
                                            size: 18,
                                          ),
                                        ],
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
              );
            },
          ),
        ),
      ],
    ),
  );
}
