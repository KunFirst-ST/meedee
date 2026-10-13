import '../../models/app_user.dart';
import 'package:flutter/material.dart';
import '../../models/shop.dart';
import '../../models/food_order.dart';
import '../../services/db.dart';
import '../../theme/app_theme.dart';
import '../../widgets/food_ui.dart';
import 'menu_screen.dart';
import 'my_orders_screen.dart';
import 'order_track_screen.dart';
import 'customer_profile_screen.dart';

class ShopListScreen extends StatefulWidget {
  final AppUser user;
  const ShopListScreen({super.key, required this.user});
  @override
  State<ShopListScreen> createState() => _ShopListScreenState();
}

class _ShopListScreenState extends State<ShopListScreen> {
  final _search = TextEditingController();
  late Stream<List<Shop>> _shops;
  late Stream<Set<String>> _favorites;
  late Stream<List<FoodOrder>> _orders;
  String _category = 'ทั้งหมด';
  bool _openOnly = false;
  int _tab = 0;
  bool _savingFavorite = false;
  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _connect() {
    _shops = Db().watchShops();
    _favorites = Db().watchFavoriteShopIds(widget.user.uid);
    _orders = Db().watchMyOrders(widget.user.uid);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _favorite(Shop shop, bool favorite) async {
    if (_savingFavorite) return;
    setState(() => _savingFavorite = true);
    try {
      await Db().setShopFavorite(widget.user.uid, shop.id, favorite);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกร้านโปรดไม่ได้ กรุณาลองใหม่')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingFavorite = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: _tab == 2
                ? MyOrdersScreen(user: widget.user, embedded: true)
                : _tab == 3
                ? CustomerProfileScreen(user: widget.user, embedded: true)
                : _discovery(),
          ),
        ],
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (i) => setState(() => _tab = i),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.explore_outlined),
          selectedIcon: Icon(Icons.explore_rounded),
          label: 'ค้นหาร้าน',
        ),
        NavigationDestination(
          icon: Icon(Icons.favorite_border_rounded),
          selectedIcon: Icon(Icons.favorite_rounded),
          label: 'ร้านโปรด',
        ),
        NavigationDestination(
          icon: Icon(Icons.receipt_long_outlined),
          selectedIcon: Icon(Icons.receipt_long_rounded),
          label: 'ออเดอร์',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline_rounded),
          selectedIcon: Icon(Icons.person_rounded),
          label: 'บัญชี',
        ),
      ],
    ),
  );
  Widget _discovery() => StreamBuilder<List<Shop>>(
    stream: _shops,
    builder: (context, snap) {
      if (snap.hasError) {
        return StatePanel(
          icon: Icons.wifi_off_rounded,
          title: 'โหลดร้านค้าไม่ได้',
          message: 'ตรวจการเชื่อมต่อ แล้วลองอีกครั้ง',
          action: 'ลองใหม่',
          onAction: () => setState(_connect),
        );
      }
      if (!snap.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return StreamBuilder<Set<String>>(
        stream: _favorites,
        builder: (context, favoriteSnap) {
          if (favoriteSnap.hasError) {
            return StatePanel(
              icon: Icons.wifi_off_rounded,
              title: 'โหลดร้านโปรดไม่ได้',
              message: 'ตรวจการเชื่อมต่อ แล้วลองอีกครั้ง',
              action: 'ลองใหม่',
              onAction: () => setState(_connect),
            );
          }
          if (!favoriteSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final favorites = favoriteSnap.data ?? <String>{};
          final all = snap.data!;
          final categories = {
            'ทั้งหมด',
            ...all
                .map((s) => s.category)
                .whereType<String>()
                .where((c) => c.isNotEmpty),
          }.toList();
          final query = _search.text.trim().toLowerCase();
          final shops =
              all
                  .where(
                    (s) =>
                        (s.name.toLowerCase().contains(query) ||
                            (s.category ?? '').toLowerCase().contains(query)) &&
                        (!_openOnly || s.isOpen) &&
                        (_category == 'ทั้งหมด' || s.category == _category) &&
                        (_tab != 1 || favorites.contains(s.id)),
                  )
                  .toList()
                ..sort(
                  (a, b) => a.isOpen == b.isOpen
                      ? a.name.compareTo(b.name)
                      : a.isOpen
                      ? -1
                      : 1,
                );
          return ContentWidth(
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: AppTheme.orange,
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: const Icon(
                              Icons.restaurant_rounded,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'MSU FOOD',
                                  style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1,
                                  ),
                                ),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.location_on_outlined,
                                      size: 14,
                                      color: AppTheme.orange,
                                    ),
                                    const SizedBox(width: 3),
                                    Flexible(
                                      child: Text(
                                        'รับอาหารที่ร้าน',
                                        style: const TextStyle(
                                          color: AppTheme.muted,
                                          fontSize: 12,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'ดูออเดอร์ของฉัน',
                            onPressed: () => setState(() => _tab = 2),
                            icon: const Icon(Icons.receipt_long_outlined),
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),
                      Text(
                        _tab == 1 ? 'มื้อโปรด ร้านประจำ' : 'วันนี้ กินอะไรดี?',
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'เลือกมื้อที่ใช่ สั่งล่วงหน้า แล้วไปรับที่ร้าน',
                        style: TextStyle(color: AppTheme.muted),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'ค้นหาร้านหรือประเภทอาหาร',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'ล้างการค้นหา',
                                  onPressed: () {
                                    _search.clear();
                                    setState(() {});
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_tab == 0 && query.isEmpty) ...[
                        Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: AppTheme.ink,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 172),
                            child: Stack(
                              children: [
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  bottom: 0,
                                  width: 170,
                                  child: Opacity(
                                    opacity: .7,
                                    child: Image.asset(
                                      'assets/images/rice.jpg',
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                Positioned.fill(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          AppTheme.ink,
                                          AppTheme.ink.withValues(alpha: .85),
                                          Colors.transparent,
                                        ],
                                        stops: const [0, .45, 1],
                                      ),
                                    ),
                                  ),
                                ),
                                const Padding(
                                  padding: EdgeInsets.all(22),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'GOOD FOOD. GOOD DAY.',
                                        style: TextStyle(
                                          color: Color(0xFFFFB599),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 2,
                                        ),
                                      ),
                                      SizedBox(height: 9),
                                      Text(
                                        'มื้ออร่อย\nไม่ต้องรอหน้าร้าน',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 24,
                                          height: 1.3,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      SizedBox(height: 10),
                                      Text(
                                        'สั่ง • ติดตาม • รับอาหาร',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                      ],
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: categories
                              .map(
                                (category) => Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(category),
                                    selected: _category == category,
                                    onSelected: (_) =>
                                        setState(() => _category = category),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _tab == 1
                                  ? 'ร้านที่บันทึกไว้'
                                  : 'เลือกร้านของคุณ',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          FilterChip(
                            label: const Text('เปิดอยู่'),
                            selected: _openOnly,
                            onSelected: (v) => setState(() => _openOnly = v),
                          ),
                        ],
                      ),
                      if (_tab == 0)
                        StreamBuilder<List<FoodOrder>>(
                          stream: _orders,
                          builder: (context, orderSnap) {
                            final active = (orderSnap.data ?? [])
                                .where(
                                  (o) => OrderStatus.active.contains(o.status),
                                )
                                .toList();
                            if (active.isEmpty) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Card(
                                color: const Color(0xFFE7F5EE),
                                child: ListTile(
                                  leading: const Icon(
                                    Icons.ramen_dining_rounded,
                                    color: AppTheme.green,
                                  ),
                                  title: Text(active.first.shopName),
                                  subtitle: Text(
                                    OrderStatus.labels[active.first.status] ??
                                        '',
                                  ),
                                  trailing: const Icon(
                                    Icons.arrow_forward_rounded,
                                  ),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => OrderTrackScreen(
                                        orderId: active.first.id,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      if (favoriteSnap.hasError)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'โหลดร้านโปรดไม่ได้ ลองเปิดหน้านี้ใหม่อีกครั้ง',
                            style: TextStyle(color: AppTheme.muted),
                          ),
                        ),
                      const SizedBox(height: 12),
                      if (shops.isEmpty)
                        StatePanel(
                          icon: _tab == 1
                              ? Icons.favorite_border_rounded
                              : Icons.search_off_rounded,
                          title: _tab == 1
                              ? 'บันทึกร้านที่ชอบไว้ที่นี่'
                              : all.isEmpty
                              ? 'ยังไม่มีร้านให้บริการ'
                              : 'ไม่พบร้านที่ค้นหา',
                          message: _tab == 1
                              ? 'แตะหัวใจบนการ์ดร้าน แล้วกลับมาสั่งได้ง่ายขึ้น'
                              : 'ลองเปลี่ยนคำค้นหาหรือตัวกรอง',
                          action: 'ล้างตัวกรอง',
                          onAction: () => setState(() {
                            _search.clear();
                            _openOnly = false;
                            _category = 'ทั้งหมด';
                          }),
                        ),
                    ]),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  sliver: SliverLayoutBuilder(
                    builder: (context, constraints) => SliverGrid(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _shopCard(
                          shops[index],
                          favorites.contains(shops[index].id),
                        ),
                        childCount: shops.length,
                      ),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: constraints.crossAxisExtent > 620
                            ? 2
                            : 1,
                        mainAxisExtent:
                            306 * MediaQuery.textScalerOf(context).scale(1),
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
  Widget _shopCard(Shop shop, bool favorite) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MenuScreen(shop: shop, user: widget.user),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 142,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  color: const Color(0xFFFFEEE7),
                  child: const Icon(
                    Icons.storefront_rounded,
                    size: 64,
                    color: AppTheme.orange,
                  ),
                ),
                Positioned(
                  left: 12,
                  top: 12,
                  child: StatusPill(
                    shop.isOpen ? 'เปิดรับออเดอร์' : 'ร้านปิดอยู่',
                    positive: shop.isOpen,
                  ),
                ),
                Positioned(
                  right: 10,
                  top: 10,
                  child: IconButton.filledTonal(
                    style: IconButton.styleFrom(backgroundColor: Colors.white),
                    tooltip: favorite ? 'นำออกจากร้านโปรด' : 'บันทึกร้านโปรด',
                    onPressed: _savingFavorite
                        ? null
                        : () => _favorite(shop, !favorite),
                    icon: Icon(
                      favorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: AppTheme.orange,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        shop.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.arrow_outward_rounded,
                      size: 19,
                      color: AppTheme.muted,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  shop.category ?? 'อาหารและเครื่องดื่ม',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      size: 17,
                      color: Color(0xFFF2A900),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      shop.reviewCount == 0
                          ? 'ยังไม่มีรีวิว'
                          : '${shop.ratingAverage?.toStringAsFixed(1) ?? '—'} · ${shop.reviewCount} รีวิว',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Icon(
                      Icons.shopping_bag_outlined,
                      size: 15,
                      color: AppTheme.orange,
                    ),
                    const SizedBox(width: 5),
                    const Text('รับที่ร้าน', style: TextStyle(fontSize: 12)),
                    if (shop.preparationMinutes != null) ...[
                      const SizedBox(width: 14),
                      const Icon(
                        Icons.schedule_rounded,
                        size: 15,
                        color: AppTheme.muted,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'ประมาณ ${shop.preparationMinutes} นาที',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
