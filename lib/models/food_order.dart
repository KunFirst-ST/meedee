import 'dart:typed_data';
import '../services/image_service.dart';

class OrderItem {
  final String name;
  final num price;
  final int qty;
  final Uint8List? imageBytes;
  final String? menuItemId;

  OrderItem({
    required this.name,
    required this.price,
    required this.qty,
    this.imageBytes,
    this.menuItemId,
  });

  num get subtotal => price * qty;

  Map<String, dynamic> toMap() => {
    'name': name,
    'price': price,
    'qty': qty,
    if (menuItemId != null) 'menuItemId': menuItemId,
    if (imageBytes != null) 'imageBase64': base64EncodeBytes(imageBytes!),
  };

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    return OrderItem(
      name: map['name'] ?? '',
      price: map['price'] ?? 0,
      qty: map['qty'] is int ? map['qty'] as int : 0,
      menuItemId: map['menuItemId'] as String?,
      imageBytes: ImageService.decode(map['imageBase64'] as String?),
    );
  }
}

String base64EncodeBytes(Uint8List bytes) => ImageService.encode(bytes);

class OrderStatus {
  static const pending = 'pending';
  static const accepted = 'accepted';
  static const cooking = 'cooking';
  static const ready = 'ready';
  static const completed = 'completed';
  static const cancelled = 'cancelled';

  static const active = [pending, accepted, cooking, ready];
  static const flow = [pending, accepted, cooking, ready, completed];

  static const labels = {
    pending: 'รอรับออเดอร์',
    accepted: 'รับออเดอร์แล้ว',
    cooking: 'กำลังปรุงอาหาร',
    ready: 'พร้อมรับที่ร้าน',
    completed: 'รับอาหารเรียบร้อย',
    cancelled: 'ยกเลิกแล้ว',
  };

  static String? actionLabel(String status) {
    switch (status) {
      case pending:
        return 'รับออเดอร์';
      case accepted:
        return 'เริ่มทำอาหาร';
      case cooking:
        return 'อาหารเสร็จแล้ว';
      case ready:
        return 'ส่งมอบเรียบร้อย';
      default:
        return null;
    }
  }

  static String? next(String status) {
    final i = flow.indexOf(status);
    if (i != -1 && i + 1 < flow.length) return flow[i + 1];
    return null;
  }

  static bool canTransition(String from, String to) =>
      next(from) == to || (from == pending && to == cancelled);
}

class FoodOrder {
  final String id;
  final String shopId;
  final String shopName;
  final String customerId;
  final String customerName;
  final List<OrderItem> items;
  final num total;
  final String status;
  final String note;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final OrderReview? review;

  FoodOrder({
    required this.id,
    required this.shopId,
    required this.shopName,
    required this.customerId,
    required this.customerName,
    required this.items,
    required this.total,
    required this.status,
    required this.note,
    this.createdAt,
    this.updatedAt,
    this.review,
  });

  factory FoodOrder.fromMap(String id, Map<String, dynamic> data) {
    if (id.isEmpty ||
        data['shopId'] is! String ||
        data['customerId'] is! String ||
        data['items'] is! List ||
        data['total'] is! num ||
        !OrderStatus.labels.containsKey(data['status'])) {
      throw const FormatException('ข้อมูลออเดอร์จากเซิร์ฟเวอร์ไม่ครบ');
    }
    final list = (data['items'] as List<dynamic>?) ?? [];
    final reviewData = data['review'];
    if (reviewData != null && reviewData is! Map<String, dynamic>) {
      throw const FormatException('ข้อมูลรีวิวจากเซิร์ฟเวอร์ไม่ถูกต้อง');
    }
    return FoodOrder(
      id: id,
      shopId: data['shopId'] ?? '',
      shopName: data['shopName'] ?? '',
      customerId: data['customerId'] ?? '',
      customerName: data['customerName'] ?? '',
      items: list
          .map((e) => OrderItem.fromMap(e as Map<String, dynamic>))
          .toList(),
      total: data['total'] ?? 0,
      status: data['status'] ?? OrderStatus.pending,
      note: data['note'] ?? '',
      createdAt: _date(data['createdAt']),
      updatedAt: _date(data['updatedAt']),
      review: reviewData == null
          ? null
          : OrderReview.fromMap(reviewData as Map<String, dynamic>),
    );
  }

  static DateTime? _date(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toLocal();
    }
    throw const FormatException('วันที่ออเดอร์จากเซิร์ฟเวอร์ไม่ถูกต้อง');
  }
}

class OrderReview {
  final int rating;
  final String? comment;

  const OrderReview({required this.rating, this.comment});

  factory OrderReview.fromMap(Map<String, dynamic> data) {
    final rating = data['rating'];
    final comment = data['comment'];
    if (rating is! int ||
        rating < 1 ||
        rating > 5 ||
        (comment != null && comment is! String)) {
      throw const FormatException('ข้อมูลรีวิวจากเซิร์ฟเวอร์ไม่ถูกต้อง');
    }
    return OrderReview(rating: rating, comment: comment as String?);
  }
}
