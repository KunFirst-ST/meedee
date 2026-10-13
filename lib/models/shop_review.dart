class ShopReview {
  final int id;
  final int rating;
  final String? comment;
  final String customerName;
  final DateTime createdAt;

  const ShopReview({
    required this.id,
    required this.rating,
    required this.comment,
    required this.customerName,
    required this.createdAt,
  });

  factory ShopReview.fromMap(Map<String, dynamic> data) {
    final date = data['createdAt'] is String
        ? DateTime.tryParse(data['createdAt'] as String)
        : null;
    if (data['id'] is! int ||
        data['rating'] is! int ||
        (data['rating'] as int) < 1 ||
        (data['rating'] as int) > 5 ||
        data['customerName'] is! String ||
        (data['comment'] != null && data['comment'] is! String) ||
        date == null) {
      throw const FormatException('ข้อมูลรีวิวไม่ครบ กรุณาลองใหม่');
    }
    return ShopReview(
      id: data['id'] as int,
      rating: data['rating'] as int,
      comment: data['comment'] as String?,
      customerName: data['customerName'] as String,
      createdAt: date,
    );
  }
}

class ShopReviewPage {
  final List<ShopReview> items;
  final int currentPage;
  final int lastPage;
  final int total;
  final double? ratingAverage;

  const ShopReviewPage({
    required this.items,
    required this.currentPage,
    required this.lastPage,
    required this.total,
    required this.ratingAverage,
  });

  bool get hasMore => currentPage < lastPage;

  factory ShopReviewPage.fromMap(Map<String, dynamic> data) {
    final items = data['items'];
    final average = data['ratingAverage'];
    if (items is! List ||
        data['currentPage'] is! int ||
        (data['currentPage'] as int) < 1 ||
        data['lastPage'] is! int ||
        (data['lastPage'] as int) < 1 ||
        data['total'] is! int ||
        (data['total'] as int) < 0 ||
        (average != null &&
            (average is! num ||
                !average.isFinite ||
                average < 1 ||
                average > 5))) {
      throw const FormatException('ข้อมูลรีวิวไม่ครบ กรุณาลองใหม่');
    }
    return ShopReviewPage(
      items: items
          .map((item) {
            if (item is! Map<String, dynamic>) {
              throw const FormatException('ข้อมูลรีวิวไม่ครบ กรุณาลองใหม่');
            }
            return ShopReview.fromMap(item);
          })
          .toList(growable: false),
      currentPage: data['currentPage'] as int,
      lastPage: data['lastPage'] as int,
      total: data['total'] as int,
      ratingAverage: (average as num?)?.toDouble(),
    );
  }
}
