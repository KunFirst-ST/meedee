import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/shop_review.dart';
import '../../services/db.dart';
import '../../theme/app_theme.dart';
import '../../widgets/food_ui.dart';

class ShopReviewsScreen extends StatefulWidget {
  final String shopId;
  final String shopName;
  final Db? database;

  const ShopReviewsScreen({
    super.key,
    required this.shopId,
    required this.shopName,
    this.database,
  });

  @override
  State<ShopReviewsScreen> createState() => _ShopReviewsScreenState();
}

class _ShopReviewsScreenState extends State<ShopReviewsScreen> {
  late final Db _db = widget.database ?? Db();
  final List<ShopReview> _reviews = [];
  ShopReviewPage? _page;
  bool _loading = true;
  String? _error;
  bool _retryReset = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (!reset && _loading) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _db.fetchShopReviews(
        widget.shopId,
        page: reset ? 1 : (_page?.currentPage ?? 0) + 1,
      );
      if (!mounted || request != _request) return;
      setState(() {
        if (reset) _reviews.clear();
        final ids = _reviews.map((r) => r.id).toSet();
        _reviews.addAll(page.items.where((r) => ids.add(r.id)));
        _page = page;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _retryReset = reset;
        _error = 'โหลดรีวิวไม่ได้ ตรวจการเชื่อมต่อแล้วลองใหม่';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('รีวิวร้าน'),
      actions: [
        IconButton(
          tooltip: 'รีเฟรชรีวิว',
          onPressed: _loading ? null : () => _load(reset: true),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: _page == null
        ? _loading
              ? const Center(child: CircularProgressIndicator())
              : StatePanel(
                  icon: Icons.wifi_off_rounded,
                  title: 'ยังโหลดรีวิวไม่ได้',
                  message: _error!,
                  action: 'ลองใหม่',
                  onAction: () => _load(reset: true),
                )
        : ContentWidth(
            child: RefreshIndicator(
              onRefresh: () => _load(reset: true),
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                itemCount: _reviews.length + 2,
                itemBuilder: (context, index) {
                  if (index == 0) return _summary();
                  if (index <= _reviews.length) {
                    return _ReviewCard(review: _reviews[index - 1]);
                  }
                  return Column(
                    children: [
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        )
                      else if (_error != null) ...[
                        Text(_error!, textAlign: TextAlign.center),
                        TextButton(
                          onPressed: () => _load(reset: _retryReset),
                          child: const Text('ลองใหม่'),
                        ),
                      ] else if (_page!.hasMore)
                        OutlinedButton(
                          onPressed: _load,
                          child: const Text('โหลดรีวิวเพิ่มเติม'),
                        ),
                      const SizedBox(height: 16),
                      const Text(
                        'ให้คะแนนและเขียนรีวิวได้จากหน้าออเดอร์ หลังรับอาหารเรียบร้อยแล้ว',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.muted, fontSize: 13),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
  );

  Widget _summary() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(widget.shopName, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              const Icon(
                Icons.star_rounded,
                color: Color(0xFFF2A900),
                size: 44,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _page!.ratingAverage?.toStringAsFixed(1) ??
                          'ยังไม่มีคะแนน',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Text('${_page!.total} รีวิวจากลูกค้าที่รับอาหารแล้ว'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      if (_reviews.isEmpty)
        const StatePanel(
          icon: Icons.rate_review_outlined,
          title: 'ร้านนี้ยังไม่มีรีวิว',
          message: 'เมื่อมีลูกค้าให้คะแนน ความคิดเห็นจะแสดงที่นี่',
        )
      else ...[
        Text(
          'ความคิดเห็นล่าสุด',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
      ],
    ],
  );
}

class _ReviewCard extends StatelessWidget {
  final ShopReview review;
  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            review.customerName,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            DateFormat('dd/MM/yyyy').format(review.createdAt.toLocal()),
            style: const TextStyle(color: AppTheme.muted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Semantics(
            label: '${review.rating} จาก 5 ดาว',
            child: Row(
              children: List.generate(
                5,
                (index) => Icon(
                  index < review.rating
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: const Color(0xFFF2A900),
                  size: 21,
                ),
              ),
            ),
          ),
          if (review.comment?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Text(review.comment!),
          ],
        ],
      ),
    ),
  );
}
