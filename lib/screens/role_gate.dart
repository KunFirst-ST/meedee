import '../models/app_user.dart';
import 'package:flutter/material.dart';
import '../services/db.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/food_ui.dart';
import 'customer/shop_list_screen.dart';
import 'shop/order_board_screen.dart';

class RoleGate extends StatefulWidget {
  final AppUser user;
  const RoleGate({super.key, required this.user});
  @override
  State<RoleGate> createState() => _RoleGateState();
}

class _RoleGateState extends State<RoleGate> {
  late Stream<Map<String, dynamic>?> _profile;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _connect() {
    _profile = Db().watchProfile(widget.user.uid);
  }

  Future<void> _signOut() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await AuthService().signOut();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ออกจากระบบไม่ได้ กรุณาลองใหม่')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick(bool shop) async {
    if (_busy) return;
    String? shopName;
    if (shop) {
      final ctrl = TextEditingController();
      shopName = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('ชื่อร้านของคุณ'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            maxLength: 120,
            decoration: const InputDecoration(hintText: 'เช่น ครัวมอ'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () {
                if (ctrl.text.trim().isNotEmpty) {
                  Navigator.pop(ctx, ctrl.text.trim());
                }
              },
              child: const Text('เปิดหน้าร้าน'),
            ),
          ],
        ),
      );
      // Dialog route may still animate while its text field disposes.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      ctrl.dispose();
      if (shopName == null || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      if (shop) {
        await Db().becomeShop(
          widget.user.uid,
          widget.user.displayName ?? 'เจ้าของร้าน',
          shopName!,
        );
      } else {
        await Db().becomeCustomer(
          widget.user.uid,
          widget.user.displayName ?? 'ลูกค้า',
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('บันทึกบทบาทไม่ได้ กรุณาตรวจการเชื่อมต่อแล้วลองใหม่'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<Map<String, dynamic>?>(
    stream: _profile,
    builder: (context, snap) {
      if (snap.hasError) {
        return Scaffold(
          body: StatePanel(
            title: 'โหลดบัญชีไม่ได้',
            message: 'ตรวจการเชื่อมต่อหรือสิทธิ์บัญชี แล้วลองอีกครั้ง',
            action: 'ลองใหม่',
            onAction: () => setState(_connect),
          ),
        );
      }
      if (snap.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final profile = snap.data;
      if (profile?['role'] == 'shop' && profile?['shopId'] is String) {
        return OrderBoardScreen(
          user: widget.user,
          shopId: profile!['shopId'] as String,
        );
      }
      if (profile?['role'] == 'customer') {
        return ShopListScreen(user: widget.user);
      }
      return Scaffold(
        appBar: AppBar(
          title: const Text('ยินดีต้อนรับ'),
          actions: [
            IconButton(
              tooltip: 'ออกจากระบบ',
              onPressed: _busy ? null : _signOut,
              icon: const Icon(Icons.logout_rounded),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'วันนี้ใช้ MSU Food\nในบทบาทไหน?',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'สลับบทบาทภายหลังได้ในหน้าบัญชี',
                    style: TextStyle(color: AppTheme.muted),
                  ),
                  const SizedBox(height: 28),
                  _role(
                    Icons.shopping_bag_outlined,
                    'สั่งอาหาร',
                    'ค้นหาร้าน เลือกมื้ออร่อย แล้วไปรับที่ร้าน',
                    () => _pick(false),
                  ),
                  const SizedBox(height: 16),
                  _role(
                    Icons.storefront_outlined,
                    'จัดการร้าน',
                    profile?['shopId'] != null
                        ? 'กลับไปจัดการร้านเดิมของคุณ'
                        : 'เพิ่มเมนู รับออเดอร์ และจัดการหน้าร้าน',
                    () => _pick(true),
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
  Widget _role(IconData icon, String title, String detail, VoidCallback tap) =>
      Card(
        child: ListTile(
          contentPadding: const EdgeInsets.all(20),
          leading: CircleAvatar(
            backgroundColor: const Color(0xFFFFEEE7),
            child: Icon(icon, color: AppTheme.accent),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(detail),
          ),
          trailing: const Icon(Icons.arrow_forward_rounded),
          onTap: _busy ? null : tap,
        ),
      );
}
