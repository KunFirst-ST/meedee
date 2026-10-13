import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/auth_validation.dart';
import '../widgets/auth_form_layout.dart';

class RegisterScreen extends StatefulWidget {
  final AuthService? authService;

  const RegisterScreen({super.key, this.authService});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  AuthService? _service;
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  AuthService get _auth => widget.authService ?? (_service ??= AuthService());

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    String? error;
    try {
      error = await _auth.registerWithEmail(
        name: _name.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
      );
    } catch (_) {
      error = 'สร้างบัญชีไม่สำเร็จ ตรวจอินเทอร์เน็ตแล้วลองอีกครั้ง';
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = error;
    });
    if (error == null) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) => AuthFormLayout(
    title: 'สร้างบัญชีของคุณ',
    subtitle:
        'บันทึกร้านโปรดและติดตามทุกมื้อได้ง่าย ๆ\nหลังสมัคร เราจะส่งอีเมลให้คุณยืนยันบัญชี',
    showBack: true,
    children: [
      AutofillGroup(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const Key('register-name'),
                controller: _name,
                enabled: !_loading,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
                validator: AuthValidation.name,
                decoration: const InputDecoration(
                  labelText: 'ชื่อที่แสดง',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('register-email'),
                controller: _email,
                enabled: !_loading,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                autocorrect: false,
                validator: AuthValidation.email,
                decoration: const InputDecoration(
                  labelText: 'อีเมล',
                  hintText: 'you@example.com',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('register-password'),
                controller: _password,
                enabled: !_loading,
                obscureText: _obscure,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                autocorrect: false,
                enableSuggestions: false,
                validator: AuthValidation.password,
                onChanged: (_) {
                  if (_confirmation.text.isNotEmpty) {
                    _formKey.currentState!.validate();
                  }
                },
                decoration: InputDecoration(
                  labelText: 'รหัสผ่าน',
                  helperText: 'อย่างน้อย 8 ตัวอักษร ควรใช้รหัสที่คาดเดาได้ยาก',
                  helperMaxLines: 3,
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    tooltip: _obscure ? 'แสดงรหัสผ่าน' : 'ซ่อนรหัสผ่าน',
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('register-confirmation'),
                controller: _confirmation,
                enabled: !_loading,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                autocorrect: false,
                enableSuggestions: false,
                validator: (value) =>
                    AuthValidation.confirmPassword(value, _password.text),
                onFieldSubmitted: (_) => _register(),
                decoration: const InputDecoration(
                  labelText: 'ยืนยันรหัสผ่าน',
                  prefixIcon: Icon(Icons.lock_outline_rounded),
                ),
              ),
              const SizedBox(height: 24),
              if (_error != null) ...[
                AuthNotice(message: _error!, isError: true),
                const SizedBox(height: 16),
              ],
              FilledButton.icon(
                key: const Key('register-submit'),
                onPressed: _loading ? null : _register,
                icon: _loading
                    ? const AuthProgress()
                    : const Icon(Icons.person_add_alt_1_rounded),
                label: Text(_loading ? 'กำลังสร้างบัญชี…' : 'สร้างบัญชี'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _loading
                    ? null
                    : () => Navigator.of(context).maybePop(),
                child: const Text('มีบัญชีแล้ว? กลับไปเข้าสู่ระบบ'),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}
