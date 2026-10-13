import '../../models/app_user.dart';
import 'package:flutter/material.dart';
import '../../models/shop.dart';
import '../../services/auth_service.dart';
import '../../services/db.dart';
import '../../theme/app_theme.dart';
import '../../widgets/food_ui.dart';
import '../account/account_help_sheet.dart';
import '../account/account_security_screen.dart';
import '../account/edit_profile_screen.dart';
import '../customer/shop_reviews_screen.dart';

class ShopProfileScreen extends StatefulWidget {
  final String shopId;
  final AppUser user;
  const ShopProfileScreen({
    super.key,
    required this.shopId,
    required this.user,
  });
  @override
  State<ShopProfileScreen> createState() => _ShopProfileScreenState();
}

class _ShopProfileScreenState extends State<ShopProfileScreen> {
  late Stream<Shop> _stream;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _stream = Db().watchShop(widget.shopId);
  }

  Future<void> _edit(Shop shop) async {
    final controllers = [
      TextEditingController(text: shop.name),
      TextEditingController(text: shop.category ?? ''),
      TextEditingController(text: shop.description ?? ''),
      TextEditingController(text: shop.location ?? ''),
      TextEditingController(text: shop.preparationMinutes?.toString() ?? ''),
    ];
    var saving = false;
    String? error;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) => PopScope(
          canPop: !saving,
          child: AlertDialog(
            title: const Text('แก้ไขข้อมูลหน้าร้าน'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Text(
                        'ระบุจุดรับอาหารและเวลาเตรียมจริงก่อนเปิดรับออเดอร์',
                      ),
                    ),
                    for (var i = 0; i < controllers.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextField(
                          controller: controllers[i],
                          enabled: !saving,
                          maxLength: [120, 80, 500, 200, 3][i],
                          keyboardType: i == 4
                              ? TextInputType.number
                              : TextInputType.text,
                          maxLines: i == 2 ? 3 : 1,
                          decoration: InputDecoration(
                            helperText: i == 3
                                ? 'เช่น อาคาร ชั้น หรือจุดนัดรับที่ลูกค้าหาเจอ'
                                : null,
                            helperMaxLines: 3,
                            labelText: [
                              'ชื่อร้าน',
                              'ประเภทอาหาร',
                              'แนะนำร้าน',
                              'จุดรับอาหาร',
                              'เวลาเตรียมอาหารโดยประมาณ (นาที)',
                            ][i],
                          ),
                        ),
                      ),
                    if (error != null)
                      Text(error!, style: const TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx),
                child: const Text('ยกเลิก'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        final minutes = int.tryParse(
                          controllers[4].text.trim(),
                        );
                        if (controllers[0].text.trim().isEmpty ||
                            minutes == null ||
                            minutes < 1 ||
                            minutes > 240) {
                          refresh(
                            () => error =
                                'ระบุชื่อร้าน และเวลาเตรียมอาหาร 1–240 นาที',
                          );
                          return;
                        }
                        refresh(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          await Db().updateShopProfile(
                            widget.shopId,
                            name: controllers[0].text,
                            category: controllers[1].text,
                            description: controllers[2].text,
                            location: controllers[3].text,
                            preparationMinutes: minutes,
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                        } catch (exception) {
                          if (ctx.mounted) {
                            refresh(() {
                              saving = false;
                              error = exception is OrderValidationException
                                  ? exception.message
                                  : 'บันทึกไม่ได้ กรุณาลองใหม่';
                            });
                          }
                        }
                      },
                child: Text(saving ? 'กำลังบันทึก…' : 'บันทึก'),
              ),
            ],
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final controller in controllers) {
      controller.dispose();
    }
  }

  Future<void> _switchRole() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('เปลี่ยนบทบาท?'),
        content: const Text(
          'ร้านจะพักรับออเดอร์ ข้อมูลร้านและประวัติเดิมยังอยู่ หากมีออเดอร์ค้างควรจัดการให้เสร็จก่อน',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('กลับ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('เลือกบทบาทใหม่'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await Db().resetRole(widget.user.uid);
      if (mounted) Navigator.popUntil(context, (r) => r.isFirst);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เปลี่ยนบทบาทไม่ได้ กรุณาลองใหม่')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ข้อมูลร้านและบัญชี')),
    body: StreamBuilder<Shop>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return StatePanel(
            title: 'โหลดข้อมูลร้านไม่ได้',
            message: 'ตรวจการเชื่อมต่อแล้วลองใหม่',
            action: 'ลองใหม่',
            onAction: () =>
                setState(() => _stream = Db().watchShop(widget.shopId)),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final shop = snap.data!;
        if (shop.ownerId != widget.user.uid) {
          return const StatePanel(
            title: 'เปิดข้อมูลร้านนี้ไม่ได้',
            message:
                'ไม่พบร้านที่บัญชีนี้เป็นเจ้าของ กรุณาตรวจบัญชีแล้วเปิดใหม่',
          );
        }
        return ContentWidth(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Card(
                color: AppTheme.ink,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.storefront_rounded,
                        color: Color(0xFFFFB599),
                        size: 40,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        shop.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      StatusPill(
                        shop.isOpen ? 'เปิดรับออเดอร์' : 'พักรับออเดอร์',
                        positive: shop.isOpen,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      title: const Text('ประเภทอาหาร'),
                      subtitle: Text(
                        shop.category?.isNotEmpty == true
                            ? shop.category!
                            : 'ยังไม่ระบุ',
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: const Text('แนะนำร้าน'),
                      subtitle: Text(
                        shop.description?.isNotEmpty == true
                            ? shop.description!
                            : 'ยังไม่ระบุ',
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: const Text('จุดรับอาหาร'),
                      subtitle: Text(
                        shop.location?.isNotEmpty == true
                            ? shop.location!
                            : 'ยังไม่ระบุ',
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      title: const Text('เวลาเตรียมโดยประมาณ'),
                      subtitle: Text(
                        shop.preparationMinutes == null
                            ? 'ยังไม่ระบุ'
                            : '${shop.preparationMinutes} นาที',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : () => _edit(shop),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('แก้ไขข้อมูลร้าน'),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.rate_review_outlined),
                  title: const Text('รีวิวจากลูกค้า'),
                  subtitle: Text('${shop.reviewCount} รีวิว'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ShopReviewsScreen(
                        shopId: shop.id,
                        shopName: shop.name,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'บัญชีเจ้าของร้าน',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.person_outline_rounded),
                      title: const Text('แก้ไขข้อมูลบัญชี'),
                      subtitle: const Text('ชื่อผู้ใช้และเบอร์ติดต่อ'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _busy
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    EditProfileScreen(user: widget.user),
                              ),
                            ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.verified_user_outlined),
                      title: const Text('บัญชีและความปลอดภัย'),
                      subtitle: const Text('สถานะอีเมลและรหัสผ่าน'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _busy
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    AccountSecurityScreen(user: widget.user),
                              ),
                            ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.help_outline_rounded),
                      title: const Text('วิธีใช้งานและคำถามที่พบบ่อย'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => showAccountHelp(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _switchRole,
                icon: const Icon(Icons.swap_horiz_rounded),
                label: const Text('เปลี่ยนบทบาทการใช้งาน'),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        try {
                          await AuthService().signOut();
                          if (context.mounted) {
                            Navigator.popUntil(context, (r) => r.isFirst);
                          }
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('ออกจากระบบไม่ได้ กรุณาลองใหม่'),
                              ),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                icon: const Icon(Icons.logout_rounded),
                label: const Text('ออกจากระบบ'),
              ),
              const SizedBox(height: 20),
              SelectableText(
                'รหัสร้าน: ${shop.id}',
                style: const TextStyle(fontSize: 12, color: AppTheme.muted),
              ),
            ],
          ),
        );
      },
    ),
  );
}
