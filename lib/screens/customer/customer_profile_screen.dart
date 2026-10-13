import '../../models/app_user.dart';
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/cart_store.dart';
import '../../services/db.dart';
import '../../theme/app_theme.dart';
import '../../widgets/food_ui.dart';
import '../account/account_help_sheet.dart';
import '../account/account_security_screen.dart';
import '../account/edit_profile_screen.dart';
import 'my_orders_screen.dart';

class CustomerProfileScreen extends StatefulWidget {
  final AppUser user;
  final bool embedded;
  const CustomerProfileScreen({
    super.key,
    required this.user,
    this.embedded = false,
  });
  @override
  State<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {
  bool _busy = false;
  Stream<Map<String, dynamic>?>? _profile;

  @override
  void initState() {
    super.initState();
    _watchProfile();
  }

  @override
  void didUpdateWidget(covariant CustomerProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid) {
      _watchProfile();
    }
  }

  void _watchProfile() {
    _profile = Db().watchProfile(widget.user.uid);
  }

  Future<void> _signOut() async {
    final user = widget.user;
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await AuthService().signOut();
      CartStore.clearAccount(user.uid);
      if (mounted) Navigator.popUntil(context, (route) => route.isFirst);
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

  Future<void> _switchRole() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('เปลี่ยนบทบาทการใช้งาน'),
        content: const Text(
          'กลับไปเลือกระหว่างลูกค้าและร้านค้า ข้อมูลร้านและออเดอร์เดิมจะยังอยู่',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('เลือกบทบาทใหม่'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await Db().resetRole(widget.user.uid);
      if (mounted) Navigator.popUntil(context, (route) => route.isFirst);
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
  Widget build(BuildContext context) {
    final body = StreamBuilder<Map<String, dynamic>?>(
      stream: _profile,
      builder: (context, snapshot) =>
          _content(profile: snapshot.data, profileError: snapshot.hasError),
    );
    return widget.embedded
        ? body
        : Scaffold(
            appBar: AppBar(title: const Text('บัญชี')),
            body: body,
          );
  }

  Widget _content({Map<String, dynamic>? profile, bool profileError = false}) {
    final user = widget.user;
    final storedName = (profile?['displayName'] as String?)?.trim();
    final name = storedName?.isNotEmpty == true
        ? storedName!
        : user.displayName ?? 'ลูกค้า';
    final phone = (profile?['phone'] as String?) ?? '';
    return ContentWidth(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('บัญชีของฉัน', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: const Color(0xFFFFEEE7),
                    child: const Icon(
                      Icons.person_rounded,
                      color: AppTheme.orange,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (phone.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            phone,
                            style: const TextStyle(color: AppTheme.muted),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          user.email ?? '',
                          style: const TextStyle(
                            color: AppTheme.muted,
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
          if (profileError) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => setState(_watchProfile),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('โหลดข้อมูลบัญชีไม่ได้ แตะเพื่อลองใหม่'),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'ข้อมูลและความปลอดภัย',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('แก้ไขข้อมูลบัญชี'),
                  subtitle: const Text('ชื่อที่ใช้รับอาหารและเบอร์ติดต่อ'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _busy
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EditProfileScreen(user: user),
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
                            builder: (_) => AccountSecurityScreen(user: user),
                          ),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('การใช้งาน', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text('ออเดอร์ของฉัน'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MyOrdersScreen(user: user),
                    ),
                  ),
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.shopping_bag_outlined),
                  title: Text('รับอาหารที่ร้าน'),
                  subtitle: Text('ชำระเงินกับร้านเมื่อไปรับอาหาร'),
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.language_rounded),
                  title: Text('ภาษาไทย'),
                  trailing: Icon(Icons.check_rounded, color: AppTheme.green),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.help_outline_rounded),
                  title: const Text('วิธีใช้งานและคำถามที่พบบ่อย'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showAccountHelp(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.swap_horiz_rounded),
                  title: const Text('เปลี่ยนบทบาท'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _busy ? null : _switchRole,
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          OutlinedButton.icon(
            onPressed: _busy ? null : _signOut,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('ออกจากระบบ'),
          ),
          const SizedBox(height: 28),
          const Center(
            child: Text(
              'MSU FOOD • มื้อดี ๆ ใกล้ตัว',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.muted,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
