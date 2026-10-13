class Shop {
  final String id;
  final String name;
  final String ownerId;
  final bool isOpen;
  final String? description;
  final String? category;
  final String? location;
  final int? preparationMinutes;
  final double? ratingAverage;
  final int reviewCount;

  Shop({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.isOpen,
    this.description,
    this.category,
    this.location,
    this.preparationMinutes,
    this.ratingAverage,
    this.reviewCount = 0,
  });

  factory Shop.fromMap(String id, Map<String, dynamic> m) {
    if (id.isEmpty ||
        m['name'] is! String ||
        (m['name'] as String).trim().isEmpty ||
        m['ownerId'] is! String ||
        (m['ownerId'] as String).isEmpty ||
        m['isOpen'] is! bool) {
      throw const FormatException('ข้อมูลร้านจากเซิร์ฟเวอร์ไม่ครบ');
    }
    final preparation = m['preparationMinutes'];
    final rating = m['ratingAverage'];
    final reviewCount = m['reviewCount'];
    return Shop(
      id: id,
      name: m['name'] as String? ?? '',
      ownerId: m['ownerId'] as String? ?? '',
      isOpen: m['isOpen'] as bool? ?? false,
      description: _optionalText(m['description']),
      category: _optionalText(m['category']),
      location: _optionalText(m['location']),
      preparationMinutes: preparation is int && preparation > 0
          ? preparation
          : null,
      ratingAverage: rating is num && rating >= 0 && rating <= 5
          ? rating.toDouble()
          : null,
      reviewCount: reviewCount is int && reviewCount >= 0 ? reviewCount : 0,
    );
  }

  static String? _optionalText(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
}
