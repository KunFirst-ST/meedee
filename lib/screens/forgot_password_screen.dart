import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/auth_validation.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_form_layout.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final AuthService? authService;

  const ForgotPasswordScreen({super.key, this.authService});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  AuthService? _service;
  Timer? _cooldownTimer;
  int _seconds = 0;
  bool _loading = false;
  bool _sent = false;
  String? _error;

  AuthService get _auth => widget.authService ?? (_service ??= AuthService());

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _email.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _seconds = 60;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _seconds--);
      if (_seconds == 0) {
        timer.cancel();
      }
    });
  }

  Future<void> _send() async {
    if (_loading || _seconds > 0 || !_formKey.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _sent = false;
    });
    String? error;
    try {
      error = await _auth.sendPasswordReset(_email.text.trim());
    } catch (_) {
      error = 'ส่งคำขอไม่สำเร็จ ตรวจอินเทอร์เน็ตแล้วลองอีกครั้ง';
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = error;
      _sent = error == null;
      _startCooldown();
    });
  }

  @override
  Widget build(BuildContext context) => AuthFormLayout(
    title: 'ตั้งรหัสผ่านใหม่',
    subtitle: 'กรอกอีเมลที่ใช้กับ MSU Food เพื่อขอลิงก์ตั้งรหัสผ่านใหม่',
    showBack: true,
    children: [
      Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: TextFormField(
          key: const Key('reset-email'),
          controller: _email,
          enabled: !_loading,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.email],
          autocorrect: false,
          validator: AuthValidation.email,
          onFieldSubmitted: (_) => _send(),
          decoration: const InputDecoration(
            labelText: 'อีเมล',
            hintText: 'you@example.com',
            prefixIcon: Icon(Icons.mail_outline_rounded),
          ),
        ),
      ),
      const SizedBox(height: 20),
      if (_sent) ...[
        const AuthNotice(
          message:
              'หากอีเมลนี้มีบัญชี คุณจะได้รับลิงก์ตั้งรหัสผ่านใหม่ '
              'โปรดตรวจกล่องจดหมายและโฟลเดอร์สแปม',
          icon: Icons.mark_email_read_outlined,
        ),
        const SizedBox(height: 20),
      ],
      if (_error != null) ...[
        AuthNotice(message: _error!, isError: true),
        const SizedBox(height: 20),
      ],
      FilledButton.icon(
        key: const Key('reset-submit'),
        onPressed: _loading || _seconds > 0 ? null : _send,
        icon: _loading
            ? const AuthProgress()
            : const Icon(Icons.forward_to_inbox_rounded),
        label: Text(
          _loading
              ? 'กำลังส่งคำขอ…'
              : _sent
              ? 'ส่งลิงก์อีกครั้ง'
              : 'ส่งลิงก์ตั้งรหัสผ่าน',
        ),
      ),
      if (_seconds > 0) ...[
        const SizedBox(height: 12),
        Text(
          'ส่งคำขออีกครั้งได้ใน $_seconds วินาที',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.muted),
        ),
      ],
      const SizedBox(height: 12),
      TextButton(
        onPressed: _loading ? null : () => Navigator.of(context).maybePop(),
        child: const Text('กลับไปเข้าสู่ระบบ'),
      ),
    ],
  );
}
