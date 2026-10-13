import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/food_order.dart';
import '../../services/db.dart';
import '../../theme/app_theme.dart';
import '../../widgets/food_ui.dart';

class OrderTrackScreen extends StatefulWidget {
  final String orderId;
  final Db? database;
  const OrderTrackScreen({super.key, required this.orderId, this.database});
  @override
  State<OrderTrackScreen> createState() => _OrderTrackScreenState();
}

class _OrderTrackScreenState extends State<OrderTrackScreen> {
  late final Db _db = widget.database ?? Db();
  late Stream<FoodOrder> _stream;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _connect() {
    _stream = _db.watchOrder(widget.orderId);
  }

  Future<void> _cancel(FoodOrder order) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยกเลิกออเดอร์นี้?'),
        content: const Text('ยกเลิกได้ขณะร้านยังไม่ได้รับออเดอร์'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('กลับ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ยืนยันยกเลิก'),
          ),
        ],
      ),
    );
    if (confirm != true || _busy || !mounted) return;
    setState(() => _busy = true);
    try {
      await _db.cancelOrder(order.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'ยกเลิกไม่ได้ ร้านอาจรับออเดอร์แล้ว กรุณาตรวจสถานะล่าสุด',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reviewOrder(FoodOrder order) async {
    if (_busy) return;
    final draft = await showDialog<_ReviewDraft>(
      context: context,
      builder: (_) => _OrderReviewDialog(shopName: order.shopName),
    );
    if (draft == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _db.reviewOrder(
        order.id,
        rating: draft.rating,
        comment: draft.comment,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ขอบคุณสำหรับรีวิวครับ')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ติดตามออเดอร์')),
    body: Column(
      children: [
        Expanded(
          child: StreamBuilder<FoodOrder>(
            stream: _stream,
            builder: (context, snap) {
              if (snap.hasError) {
                return StatePanel(
                  icon: Icons.wifi_off_rounded,
                  title: 'โหลดออเดอร์ไม่ได้',
                  message: 'ตรวจการเชื่อมต่อและบัญชีที่สั่งอาหาร',
                  action: 'ลองใหม่',
                  onAction: () => setState(_connect),
                );
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final order = snap.data!;
              final current = OrderStatus.flow.indexOf(order.status);
              final cancelled = order.status == OrderStatus.cancelled;
              final ready = order.status == OrderStatus.ready;
              final completed = order.status == OrderStatus.completed;
              return ContentWidth(
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Center(
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: cancelled
                              ? const Color(0xFFF1F2F4)
                              : const Color(0xFFFFEEE7),
                          borderRadius: BorderRadius.circular(32),
                        ),
                        child: Icon(
                          cancelled
                              ? Icons.cancel_outlined
                              : ready || completed
                              ? Icons.shopping_bag_rounded
                              : Icons.ramen_dining_rounded,
                          size: 48,
                          color: AppTheme.orange,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      cancelled
                          ? 'ออเดอร์ถูกยกเลิกแล้ว'
                          : ready
                          ? 'มื้ออร่อยพร้อมแล้ว!'
                          : completed
                          ? 'ขอบคุณสำหรับมื้อนี้'
                          : 'กำลังเตรียมมื้ออร่อยให้คุณ',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      cancelled
                          ? 'คุณสามารถกลับไปเลือกมื้อใหม่ได้'
                          : ready
                          ? 'แสดงเลขออเดอร์นี้ให้ร้านตอนรับอาหาร'
                          : completed
                          ? 'ร้านยืนยันส่งมอบอาหารเรียบร้อยแล้ว'
                          : 'ติดตามสถานะจากร้านได้ที่นี่',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.muted),
                    ),
                    const SizedBox(height: 22),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Text(
                              order.shopName,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'เลขออเดอร์',
                              style: TextStyle(
                                color: AppTheme.muted,
                                fontSize: 12,
                              ),
                            ),
                            SelectableText(
                              order.id.length > 10
                                  ? '#${order.id.substring(order.id.length - 8).toUpperCase()}'
                                  : '#${order.id}',
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(text: order.id),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('คัดลอกเลขออเดอร์แล้ว'),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.copy_rounded, size: 16),
                              label: const Text('คัดลอกเลขเต็ม'),
                            ),
                            const StatusPill('รับอาหารและชำระเงินที่ร้าน'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'สถานะจากร้าน',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    if (!cancelled)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              for (var i = 0; i < OrderStatus.flow.length; i++)
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Column(
                                      children: [
                                        Icon(
                                          i <= current
                                              ? Icons.check_circle_rounded
                                              : Icons
                                                    .radio_button_unchecked_rounded,
                                          color: i <= current
                                              ? AppTheme.green
                                              : AppTheme.line,
                                        ),
                                        if (i < OrderStatus.flow.length - 1)
                                          Container(
                                            width: 2,
                                            height: 30,
                                            color: i < current
                                                ? AppTheme.green
                                                : AppTheme.line,
                                          ),
                                      ],
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          OrderStatus.labels[OrderStatus
                                                  .flow[i]] ??
                                              '',
                                          style: TextStyle(
                                            fontWeight: i == current
                                                ? FontWeight.w800
                                                : FontWeight.w400,
                                            color: i <= current
                                                ? AppTheme.ink
                                                : AppTheme.muted,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    Text(
                      'รายละเอียดมื้อนี้',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            for (final item in order.items)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: Row(
                                  children: [
                                    Text(
                                      '${item.qty} ×',
                                      style: const TextStyle(
                                        color: AppTheme.muted,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(child: Text(item.name)),
                                    Text(
                                      money(item.subtotal),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const Divider(),
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'ยอดรวม',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
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
                          ],
                        ),
                      ),
                    ),
                    if (order.note.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text('หมายเหตุถึงร้าน: ${order.note}'),
                      ),
                    if (completed) ...[
                      const SizedBox(height: 18),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: order.review == null
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'มื้อนี้เป็นอย่างไรบ้าง?',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'รีวิวจากคุณช่วยให้ร้านพัฒนามื้อถัดไป',
                                      style: TextStyle(color: AppTheme.muted),
                                    ),
                                    const SizedBox(height: 12),
                                    FilledButton.icon(
                                      onPressed: _busy
                                          ? null
                                          : () => _reviewOrder(order),
                                      icon: const Icon(Icons.star_rounded),
                                      label: Text(
                                        _busy
                                            ? 'กำลังส่งรีวิว…'
                                            : 'ให้คะแนนร้านนี้',
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'ขอบคุณที่รีวิว',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        for (var value = 1; value <= 5; value++)
                                          Icon(
                                            value <= order.review!.rating
                                                ? Icons.star_rounded
                                                : Icons.star_border_rounded,
                                            color: const Color(0xFFF2A900),
                                            size: 20,
                                          ),
                                      ],
                                    ),
                                    if (order.review!.comment?.isNotEmpty ==
                                        true) ...[
                                      const SizedBox(height: 8),
                                      Text(order.review!.comment!),
                                    ],
                                  ],
                                ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    if (order.status == OrderStatus.pending)
                      OutlinedButton(
                        onPressed: _busy ? null : () => _cancel(order),
                        child: Text(_busy ? 'กำลังยกเลิก…' : 'ยกเลิกออเดอร์'),
                      ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () =>
                          Navigator.popUntil(context, (route) => route.isFirst),
                      child: const Text('กลับไปเลือกร้าน'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _ReviewDraft {
  final int rating;
  final String comment;

  const _ReviewDraft({required this.rating, required this.comment});
}

/// Owns the text controller for the lifetime of the dialog route. The route's
/// reverse animation can rebuild its TextField after Navigator.pop completes,
/// so the controller must not be disposed by the caller immediately on pop.
class _OrderReviewDialog extends StatefulWidget {
  final String shopName;

  const _OrderReviewDialog({required this.shopName});

  @override
  State<_OrderReviewDialog> createState() => _OrderReviewDialogState();
}

class _OrderReviewDialogState extends State<_OrderReviewDialog> {
  final _comment = TextEditingController();
  int _rating = 5;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('รีวิวมื้อนี้'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.shopName, style: const TextStyle(color: AppTheme.muted)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var value = 1; value <= 5; value++)
              IconButton(
                tooltip: '$value ดาว',
                onPressed: () => setState(() => _rating = value),
                icon: Icon(
                  value <= _rating
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  color: const Color(0xFFF2A900),
                  size: 32,
                ),
              ),
          ],
        ),
        TextField(
          controller: _comment,
          maxLength: 500,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'เล่าความประทับใจ (ไม่บังคับ)',
            alignLabelWithHint: true,
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('ยกเลิก'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          _ReviewDraft(rating: _rating, comment: _comment.text),
        ),
        child: const Text('ส่งรีวิว'),
      ),
    ],
  );
}
