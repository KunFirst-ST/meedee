import '../../models/app_user.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/auth_validation.dart';
import '../../theme/app_theme.dart';
import '../../widgets/food_ui.dart';

class AccountSecurityScreen extends StatefulWidget {
  final AppUser user;
  final AuthService? authService;

  const AccountSecurityScreen({
    super.key,
    required this.user,
    this.authService,
  });

  @override
  State<AccountSecurityScreen> createState() => _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends State<AccountSecurityScreen> {
  late final _auth = widget.authService ?? AuthService();
  final _passwordForm = GlobalKey<FormState>();
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmation = TextEditingController();
  Stream<AppUser?>? _userChanges;
  AppUser? _initialUser;
  String? _busyAction;
  String? _error;
  bool _hideCurrent = true;
  bool _hideNew = true;
  bool _hideConfirmation = true;

  bool get _busy => _busyAction != null;

  @override
  void initState() {
    super.initState();
    _initialUser = widget.user;
    _userChanges = _auth.userChanges;
  }

  Future<void> _perform(
    String action,
    Future<String?> Function() operation,
    String success,
  ) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busyAction = action;
      _error = null;
    });
    try {
      final error = await operation();
      if (!mounted) return;
      if (error != null) {
        setState(() => _error = error);
        return;
      }
      if (action == 'password') {
        _currentPassword.clear();
        _newPassword.clear();
        _confirmation.clear();
        _passwordForm.currentState?.reset();
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'ดำเนินการไม่ได้ ตรวจการเชื่อมต่อแล้วลองใหม่');
      }
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  void _changePassword() {
    if (_busy || !_passwordForm.currentState!.validate()) return;
    _perform(
      'password',
      () => _auth.changePassword(
        currentPassword: _currentPassword.text,
        newPassword: _newPassword.text,
      ),
      'เปลี่ยนรหัสผ่านแล้ว ใช้รหัสใหม่ในการเข้าสู่ระบบครั้งต่อไป',
    );
  }

  @override
  void dispose() {
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('บัญชีและความปลอดภัย')),
      body: StreamBuilder<AppUser?>(
        stream: _userChanges,
        initialData: _initialUser,
        builder: (context, snapshot) {
          final user = snapshot.data;
          if (user == null) {
            return StatePanel(
              icon: Icons.lock_outline_rounded,
              title: 'กรุณาเข้าสู่ระบบอีกครั้ง',
              message: 'เซสชันบัญชีสิ้นสุดแล้ว',
              action: 'กลับหน้าล็อกอิน',
              onAction: () =>
                  Navigator.popUntil(context, (route) => route.isFirst),
            );
          }
          return _accountContent(user);
        },
      ),
    ),
  );

  Widget _accountContent(AppUser user) {
    final providers = user.providers;
    final hasPassword = providers.contains('password');
    final hasGoogle = providers.contains('google');
    final providerLabel = [
      if (hasPassword) 'อีเมลและรหัสผ่าน',
      if (hasGoogle) 'Google',
    ].join(' • ');
    return ContentWidth(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('บัญชีของคุณ', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text(
            'ตรวจอีเมลและจัดการวิธีเข้าสู่ระบบได้ที่นี่',
            style: TextStyle(color: AppTheme.muted),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.verified_user_outlined,
                    color: AppTheme.accent,
                    size: 32,
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    user.email ?? 'บัญชีนี้ไม่มีอีเมล',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'เข้าสู่ระบบด้วย ${providerLabel.isEmpty ? 'ผู้ให้บริการบัญชี' : providerLabel}',
                    style: const TextStyle(color: AppTheme.muted),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Icon(
                        user.emailVerified
                            ? Icons.check_circle_outline
                            : Icons.mark_email_unread_outlined,
                        color: user.emailVerified
                            ? AppTheme.green
                            : AppTheme.accent,
                      ),
                      Text(
                        user.emailVerified
                            ? 'ยืนยันอีเมลแล้ว'
                            : 'ยังไม่ได้ยืนยันอีเมล',
                      ),
                    ],
                  ),
                  if (!user.emailVerified && user.email != null) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'เปิดลิงก์ในอีเมลยืนยัน แล้วกลับมากดตรวจสอบสถานะ',
                      style: TextStyle(color: AppTheme.muted),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _perform(
                                'verify',
                                _auth.sendVerificationEmail,
                                'ส่งอีเมลยืนยันแล้ว ตรวจกล่องจดหมายและสแปม',
                              ),
                        icon: const Icon(Icons.send_outlined),
                        label: Text(
                          _busyAction == 'verify'
                              ? 'กำลังส่ง…'
                              : 'ส่งอีเมลยืนยัน',
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _perform(
                              'refresh',
                              _auth.refreshUser,
                              'อัปเดตสถานะบัญชีแล้ว',
                            ),
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(
                        _busyAction == 'refresh'
                            ? 'กำลังตรวจสอบ…'
                            : 'ตรวจสอบสถานะบัญชี',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 18),
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
          const SizedBox(height: 28),
          if (hasPassword) ...[
            Text(
              'เปลี่ยนรหัสผ่าน',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'ยืนยันรหัสผ่านเดิมก่อนตั้งรหัสใหม่อย่างน้อย 8 ตัวอักษร',
              style: TextStyle(color: AppTheme.muted),
            ),
            const SizedBox(height: 20),
            Form(
              key: _passwordForm,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _passwordField(
                    controller: _currentPassword,
                    label: 'รหัสผ่านปัจจุบัน',
                    hidden: _hideCurrent,
                    onToggle: () =>
                        setState(() => _hideCurrent = !_hideCurrent),
                    validator: AuthValidation.loginPassword,
                  ),
                  const SizedBox(height: 16),
                  _passwordField(
                    controller: _newPassword,
                    label: 'รหัสผ่านใหม่',
                    hidden: _hideNew,
                    onToggle: () => setState(() => _hideNew = !_hideNew),
                    validator: (value) {
                      final error = AuthValidation.password(value);
                      if (error != null) return error;
                      if (value == _currentPassword.text) {
                        return 'กรุณาใช้รหัสใหม่ที่ต่างจากรหัสเดิม';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _passwordField(
                    controller: _confirmation,
                    label: 'ยืนยันรหัสผ่านใหม่',
                    hidden: _hideConfirmation,
                    onToggle: () =>
                        setState(() => _hideConfirmation = !_hideConfirmation),
                    validator: (value) => AuthValidation.confirmPassword(
                      value,
                      _newPassword.text,
                    ),
                    last: true,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _busy ? null : _changePassword,
                    icon: _busyAction == 'password'
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_reset_rounded),
                    label: Text(
                      _busyAction == 'password'
                          ? 'กำลังเปลี่ยนรหัส…'
                          : 'บันทึกรหัสผ่านใหม่',
                    ),
                  ),
                ],
              ),
            ),
          ] else
            Card(
              child: ListTile(
                leading: const Icon(Icons.lock_outline_rounded),
                title: Text(
                  hasGoogle ? 'จัดการรหัสผ่านผ่าน Google' : 'วิธีเข้าสู่ระบบ',
                ),
                subtitle: Text(
                  hasGoogle
                      ? 'บัญชีนี้เข้าสู่ระบบผ่าน Google จัดการรหัสผ่านได้ในการตั้งค่าบัญชี Google ของคุณ'
                      : 'บัญชีนี้ไม่มีรหัสผ่านอีเมลที่เปลี่ยนผ่านแอปได้',
                ),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool hidden,
    required VoidCallback onToggle,
    required String? Function(String?) validator,
    bool last = false,
  }) => TextFormField(
    controller: controller,
    enabled: !_busy,
    obscureText: hidden,
    autocorrect: false,
    enableSuggestions: false,
    keyboardType: TextInputType.visiblePassword,
    textInputAction: last ? TextInputAction.done : TextInputAction.next,
    validator: validator,
    onFieldSubmitted: last ? (_) => _changePassword() : null,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: const Icon(Icons.lock_outline),
      suffixIcon: IconButton(
        tooltip: hidden ? 'แสดง$label' : 'ซ่อน$label',
        onPressed: _busy ? null : onToggle,
        icon: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off),
      ),
    ),
  );
}
