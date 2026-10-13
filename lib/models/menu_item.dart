import 'dart:typed_data';
import '../services/image_service.dart';

class MenuItem {
  final String id;
  final String name;
  final num price;
  final bool available;
  final Uint8List? imageBytes;
  final String? shopId;
  final String? category;
  final String? description;

  MenuItem({
    required this.id,
    required this.name,
    required this.price,
    required this.available,
    this.imageBytes,
    this.shopId,
    this.category,
    this.description,
  });

  factory MenuItem.fromMap(String id, Map<String, dynamic> data) {
    final price = data['price'];
    if (id.isEmpty ||
        data['name'] is! String ||
        (data['name'] as String).trim().isEmpty ||
        price is! num ||
        !price.isFinite ||
        price <= 0 ||
        data['available'] is! bool ||
        data['shopId'] is! String ||
        (data['shopId'] as String).isEmpty) {
      throw const FormatException('ข้อมูลเมนูจากเซิร์ฟเวอร์ไม่ครบ');
    }
    return MenuItem(
      id: id,
      name: data['name'] ?? '',
      price: data['price'] ?? 0,
      available: data['available'] == true,
      imageBytes: ImageService.decode(data['imageBase64'] as String?),
      shopId: data['shopId'] as String?,
      category: _optionalText(data['category']),
      description: _optionalText(data['description']),
    );
  }

  static String? _optionalText(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
}
