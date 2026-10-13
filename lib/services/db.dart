import 'dart:async';
import 'dart:math';
import 'api_client.dart';
import 'auth_service.dart';
import '../models/shop.dart';
import '../models/shop_review.dart';
import '../models/menu_item.dart';
import '../models/food_order.dart';

class OrderValidationException implements Exception {
  final String message;
  const OrderValidationException(this.message);

  @override
  String toString() => message;
}

class ProfileValidationException implements Exception {
  final String message;
  const ProfileValidationException(this.message);

  @override
  String toString() => message;
}

/// Canonical profile values shared by account forms and API writes.
/// A phone number is optional; these checks do not verify phone ownership.
class ProfileValidation {
  static String normalizeName(String value) {
    final name = value.trim();
    if (name.isEmpty || name.length > 120) {
      throw const ProfileValidationException('ชื่อต้องมี 1–120 ตัวอักษร');
    }
    return name;
  }

  static String normalizePhone(String value) {
    final phone = value.trim().replaceAll(RegExp(r'[\s()\-]'), '');
    if (phone.isNotEmpty && !RegExp(r'^\+?[0-9]{8,15}$').hasMatch(phone)) {
      throw const ProfileValidationException(
        'กรอกเบอร์โทร 8–15 หลัก เช่น 0812345678 หรือ +66812345678',
      );
    }
    return phone;
  }
}

/// Shared checkout constraints. The backend independently enforces the same limits.
/// The eight-item limit is a product checkout limit.
class OrderValidation {
  static const maxDistinctItems = 8;
  static const maxQuantity = 99;
  static const maxUnitPrice = 100000;
  static const maxNoteLength = 500;

  static int priceInSatang(num price) {
    if (!price.isFinite || price <= 0 || price > maxUnitPrice) {
      throw const OrderValidationException('ราคาอาหารไม่ถูกต้อง');
    }
    final satang = (price * 100).round();
    if ((price * 100 - satang).abs() > 0.000001) {
      throw const OrderValidationException(
        'ราคาอาหารต้องมีทศนิยมไม่เกิน 2 ตำแหน่ง',
      );
    }
    return satang;
  }

  static num totalFor(List<OrderItem> items) {
    if (items.isEmpty) {
      throw const OrderValidationException('กรุณาเพิ่มอาหารในตะกร้า');
    }
    if (items.length > maxDistinctItems) {
      throw const OrderValidationException('สั่งได้สูงสุด 8 เมนูต่อออเดอร์');
    }
    final ids = <String>{};
    var totalSatang = 0;
    for (final item in items) {
      final id = item.menuItemId;
      if (id == null || id.isEmpty || id.length > 128 || id.contains('/')) {
        throw const OrderValidationException('กรุณาเลือกเมนูใหม่จากหน้าร้าน');
      }
      if (!ids.add(id)) {
        throw const OrderValidationException('กรุณารวมจำนวนของเมนูเดียวกัน');
      }
      if (item.qty < 1 || item.qty > maxQuantity) {
        throw const OrderValidationException('จำนวนอาหารต้องอยู่ระหว่าง 1–99');
      }
      totalSatang += priceInSatang(item.price) * item.qty;
    }
    return totalSatang / 100;
  }

  static void validateNote(String note) {
    if (note.trim().length > maxNoteLength) {
      throw const OrderValidationException('หมายเหตุต้องไม่เกิน 500 ตัวอักษร');
    }
  }

  /// Reject stale prices instead of charging a different amount without consent.
  static List<OrderItem> revalidateItems({
    required String shopId,
    required List<OrderItem> items,
    required Map<String, MenuItem> latestMenu,
  }) {
    totalFor(items);
    return items
        .map((item) {
          final latest = latestMenu[item.menuItemId];
          if (latest == null || latest.shopId != shopId) {
            throw OrderValidationException('ไม่พบเมนู ${item.name} ในร้านนี้');
          }
          if (!latest.available) {
            throw OrderValidationException(
              '${latest.name} หมดแล้ว กรุณาปรับตะกร้า',
            );
          }
          if (priceInSatang(latest.price) != priceInSatang(item.price)) {
            throw OrderValidationException(
              'ราคา ${latest.name} เปลี่ยนแล้ว กรุณาตรวจสอบตะกร้าก่อนสั่งอีกครั้ง',
            );
          }
          return OrderItem(
            menuItemId: latest.id,
            name: latest.name,
            price: latest.price,
            qty: item.qty,
          );
        })
        .toList(growable: false);
  }
}

class ShopReadiness {
  static void requireReady(Shop shop) {
    if (shop.location == null || shop.location!.trim().isEmpty) {
      throw const OrderValidationException(
        'กรุณาระบุจุดรับอาหารจริงในข้อมูลร้านก่อนเปิดรับออเดอร์',
      );
    }
    final minutes = shop.preparationMinutes;
    if (minutes == null || minutes < 1 || minutes > 240) {
      throw const OrderValidationException(
        'กรุณาระบุเวลาเตรียมอาหารจริง 1–240 นาทีในข้อมูลร้าน',
      );
    }
  }
}

class Db {
  final ApiClient _api;
  final AuthService _auth;
  final Duration refreshInterval;
  static final _changes = StreamController<void>.broadcast();

  Db({
    ApiClient? client,
    AuthService? auth,
    this.refreshInterval = const Duration(seconds: 5),
  }) : _api = client ?? ApiClient.instance,
       _auth = auth ?? AuthService.instance;

  String _requireActor() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw const OrderValidationException('กรุณาเข้าสู่ระบบก่อนดำเนินการ');
    }
    return uid;
  }

  void _requireSelf(String uid) {
    if (_requireActor() != uid) {
      throw const OrderValidationException(
        'ไม่สามารถแก้ไขข้อมูลของผู้ใช้อื่นได้',
      );
    }
  }

  String _id(String value) {
    if (value.isEmpty || value.length > 128 || value.contains('/')) {
      throw const OrderValidationException('รหัสข้อมูลไม่ถูกต้อง');
    }
    return Uri.encodeComponent(value);
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const OrderValidationException(
        'เซิร์ฟเวอร์ส่งข้อมูลไม่ครบ กรุณาลองใหม่',
      );
    }
    return value;
  }

  List<Map<String, dynamic>> _rows(Object? value) {
    if (value is! List) {
      throw const OrderValidationException(
        'เซิร์ฟเวอร์ส่งรายการไม่ครบ กรุณาลองใหม่',
      );
    }
    return value.map(_map).toList(growable: false);
  }

  Future<dynamic> _call(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    _requireActor();
    try {
      return await _api.request(method, path, body: body);
    } on ApiException catch (error) {
      throw OrderValidationException(error.message);
    }
  }

  Future<dynamic> _write(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final result = await _call(method, path, body: body);
    _changes.add(null);
    return result;
  }

  /// Read actual server data; cancel timers and suppress stale-account responses.
  Stream<T> _poll<T>(Future<T> Function() read) {
    final actor = _requireActor();
    late StreamController<T> controller;
    Timer? timer;
    StreamSubscription<void>? mutations;
    var cancelled = true;
    var loading = false;
    var repeat = false;
    Future<void> refresh() async {
      if (cancelled) {
        return;
      }
      if (_auth.currentUser?.uid != actor) {
        await controller.close();
        return;
      }
      if (loading) {
        repeat = true;
        return;
      }
      loading = true;
      try {
        final value = await read();
        if (!cancelled &&
            !controller.isClosed &&
            _auth.currentUser?.uid == actor) {
          controller.add(value);
        }
      } catch (error, stack) {
        if (!cancelled &&
            !controller.isClosed &&
            _auth.currentUser?.uid == actor) {
          controller.addError(error, stack);
        }
      } finally {
        loading = false;
        if (repeat && !cancelled) {
          repeat = false;
          unawaited(refresh());
        }
      }
    }

    controller = StreamController<T>.broadcast(
      onListen: () {
        if (controller.isClosed) return;
        cancelled = false;
        mutations = _changes.stream.listen((_) => unawaited(refresh()));
        timer = Timer.periodic(refreshInterval, (_) => unawaited(refresh()));
        unawaited(refresh());
      },
      onCancel: () {
        cancelled = true;
        timer?.cancel();
        timer = null;
        final subscription = mutations;
        mutations = null;
        if (subscription != null) unawaited(subscription.cancel());
      },
    );
    return controller.stream;
  }

  Stream<Map<String, dynamic>?> watchProfile(String uid) {
    _requireSelf(uid);
    return _poll(() async => _map(await _call('GET', '/profile')));
  }

  Future<void> updateProfile(
    String uid, {
    required String displayName,
    required String phone,
  }) async {
    _requireSelf(uid);
    await _write(
      'PATCH',
      '/profile',
      body: {
        'displayName': ProfileValidation.normalizeName(displayName),
        'phone': ProfileValidation.normalizePhone(phone),
      },
    );
  }

  Future<void> becomeCustomer(String uid, String name) async {
    _requireSelf(uid);
    await _write('POST', '/profile/role', body: {'role': 'customer'});
  }

  Future<void> becomeShop(String uid, String name, String shopName) async {
    _requireSelf(uid);
    await _write(
      'POST',
      '/profile/role',
      body: {
        'role': 'shop',
        'shopName': ProfileValidation.normalizeName(shopName),
      },
    );
  }

  Stream<Shop> watchShop(String shopId) => _poll(() async {
    final data = _map(await _call('GET', '/shops/${_id(shopId)}'));
    return Shop.fromMap(data['id'] as String? ?? shopId, data);
  });

  Future<ShopReviewPage> fetchShopReviews(String shopId, {int page = 1}) async {
    if (page < 1) {
      throw const OrderValidationException('หน้ารายการรีวิวไม่ถูกต้อง');
    }
    return ShopReviewPage.fromMap(
      _map(await _call('GET', '/shops/${_id(shopId)}/reviews?page=$page')),
    );
  }

  Future<void> setShopOpen(String shopId, bool isOpen) async {
    await _write(
      'PATCH',
      '/shops/${_id(shopId)}/open',
      body: {'isOpen': isOpen},
    );
  }

  Future<void> updateShopProfile(
    String shopId, {
    required String name,
    required String category,
    required String description,
    required String location,
    required int preparationMinutes,
  }) async {
    final validName = ProfileValidation.normalizeName(name);
    if (category.trim().length > 80 ||
        description.trim().length > 500 ||
        location.trim().length > 200 ||
        preparationMinutes < 1 ||
        preparationMinutes > 240) {
      throw const OrderValidationException(
        'กรุณาตรวจข้อมูลร้านและเวลาเตรียมอาหาร (1–240 นาที)',
      );
    }
    await _write(
      'PATCH',
      '/shops/${_id(shopId)}',
      body: {
        'name': validName,
        'category': category.trim(),
        'description': description.trim(),
        'location': location.trim(),
        'preparationMinutes': preparationMinutes,
      },
    );
  }

  Stream<List<Shop>> watchShops() => _poll(
    () async => _rows(await _call('GET', '/shops'))
        .map((data) => Shop.fromMap(data['id'] as String, data))
        .toList(growable: false),
  );

  Stream<Set<String>> watchFavoriteShopIds(String uid) {
    _requireSelf(uid);
    return _poll(() async {
      final ids = await _call('GET', '/favorites');
      if (ids is! List || ids.any((id) => id is! String)) {
        throw const OrderValidationException('โหลดร้านโปรดไม่ได้ กรุณาลองใหม่');
      }
      return ids.cast<String>().toSet();
    });
  }

  Future<void> setShopFavorite(String uid, String shopId, bool favorite) async {
    _requireSelf(uid);
    await _write(
      'PUT',
      '/favorites/${_id(shopId)}',
      body: {'favorite': favorite},
    );
  }

  Stream<List<MenuItem>> watchMenu(String shopId) => _poll(
    () async => _rows(await _call('GET', '/shops/${_id(shopId)}/menu'))
        .map((data) => MenuItem.fromMap(data['id'] as String, data))
        .toList(growable: false),
  );

  Future<void> addMenuItem(
    String shopId,
    String name,
    num price, {
    String? imageBase64,
    String? category,
    String? description,
  }) async {
    await _write(
      'POST',
      '/shops/${_id(shopId)}/menu',
      body: {
        'name': ProfileValidation.normalizeName(name),
        'priceSatang': OrderValidation.priceInSatang(price),
        'available': true,
        'imageBase64': ?imageBase64,
        if (category != null) 'category': category.trim(),
        if (description != null) 'description': description.trim(),
      },
    );
  }

  Future<void> updateMenuItem(
    String id,
    String name,
    num price, {
    String? imageBase64,
    bool removeImage = false,
    String? category,
    String? description,
  }) async {
    await _write(
      'PATCH',
      '/menu/${_id(id)}',
      body: {
        'name': ProfileValidation.normalizeName(name),
        'priceSatang': OrderValidation.priceInSatang(price),
        'imageBase64': ?imageBase64,
        if (removeImage && imageBase64 == null) 'imageBase64': null,
        if (category != null) 'category': category.trim(),
        if (description != null) 'description': description.trim(),
      },
    );
  }

  Future<void> setAvailable(String id, bool value) async {
    await _write(
      'PATCH',
      '/menu/${_id(id)}/available',
      body: {'available': value},
    );
  }

  Future<void> deleteMenuItem(String id) async {
    await _write('DELETE', '/menu/${_id(id)}');
  }

  Future<String> placeOrder({
    required Shop shop,
    required String customerId,
    required String customerName,
    required List<OrderItem> items,
    required String note,
    String? requestId,
  }) async {
    _requireSelf(customerId);
    OrderValidation.totalFor(items);
    OrderValidation.validateNote(note);
    final random = Random.secure();
    final key =
        requestId ??
        List.generate(
          16,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(key)) {
      throw const OrderValidationException('รหัสการสั่งซื้อไม่ถูกต้อง');
    }
    final data = _map(
      await _write(
        'POST',
        '/orders',
        body: {
          'shopId': shop.id,
          'requestId': key,
          'note': note.trim(),
          'items': items
              .map(
                (item) => {
                  'menuItemId': item.menuItemId,
                  'qty': item.qty,
                  'expectedPriceSatang': OrderValidation.priceInSatang(
                    item.price,
                  ),
                },
              )
              .toList(growable: false),
        },
      ),
    );
    final id = data['id'];
    if (id is! String || id.isEmpty) {
      throw const OrderValidationException(
        'ยังยืนยันหมายเลขออเดอร์ไม่ได้ กรุณาลองใหม่',
      );
    }
    return id;
  }

  List<FoodOrder> _orders(Object? data) => _rows(data)
      .map((row) => FoodOrder.fromMap(row['id'] as String, row))
      .toList(growable: false);

  Stream<List<FoodOrder>> watchShopOrders(String shopId) => _poll(
    () async => _orders(
      await _call('GET', '/shops/${_id(shopId)}/orders?history=false'),
    ),
  );

  Stream<List<FoodOrder>> watchShopOrderHistory(String shopId) => _poll(
    () async => _orders(
      await _call('GET', '/shops/${_id(shopId)}/orders?history=true'),
    ),
  );

  Stream<List<FoodOrder>> watchMyOrders(String customerId) {
    _requireSelf(customerId);
    return _poll(() async => _orders(await _call('GET', '/orders')));
  }

  Stream<FoodOrder> watchOrder(String orderId) => _poll(() async {
    final data = _map(await _call('GET', '/orders/${_id(orderId)}'));
    return FoodOrder.fromMap(data['id'] as String? ?? orderId, data);
  });

  Future<String?> acceptOrder(String orderId) async {
    try {
      await _write('POST', '/orders/${_id(orderId)}/accept');
      return null;
    } catch (error) {
      return error.toString();
    }
  }

  Future<void> advanceStatus(String orderId, String current) async {
    final next = OrderStatus.next(current);
    if (next == null) {
      throw const OrderValidationException('ออเดอร์นี้ไม่มีสถานะถัดไป');
    }
    await _write(
      'PATCH',
      '/orders/${_id(orderId)}/status',
      body: {'currentStatus': current, 'nextStatus': next},
    );
  }

  Future<void> cancelOrder(String orderId) async {
    await _write('POST', '/orders/${_id(orderId)}/cancel');
  }

  Future<void> reviewOrder(
    String orderId, {
    required int rating,
    required String comment,
  }) async {
    if (rating < 1 || rating > 5 || comment.trim().length > 500) {
      throw const OrderValidationException('กรุณาตรวจคะแนนและข้อความรีวิว');
    }
    await _write(
      'POST',
      '/orders/${_id(orderId)}/review',
      body: {'rating': rating, 'comment': comment.trim()},
    );
  }

  Future<void> resetRole(String uid) async {
    _requireSelf(uid);
    await _write('DELETE', '/profile/role');
  }
}
