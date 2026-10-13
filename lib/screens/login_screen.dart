import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/auth_validation.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_form_layout.dart';
import '../widgets/google_sign_in_button.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  final AuthService? authService;
  final String? connectionError;
  final VoidCallback? onRetryConnection;

  const LoginScreen({
    super.key,
    this.authService,
    this.connectionError,
    this.onRetryConnection,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  AuthService? _service;
  String? _error;
  String? _notice;
  bool _errorIsGoogle = false;
  String? _busy;
  bool _obscure = true;

  AuthService get _auth => widget.authService ?? (_service ??= AuthService());

  @override
  void initState() {
    super.initState();
    _error = _auth.lastOAuthError;
    _errorIsGoogle = _error != null;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn({bool google = false}) async {
    if (_busy != null) return;
    if (!google && !_formKey.currentState!.validate()) {
      if (_notice != null) setState(() => _notice = null);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = google ? 'google' : 'email';
      _error = null;
      _notice = null;
      _errorIsGoogle = google;
    });
    String? error;
    String? notice;
    try {
      if (google) {
        final result = await _auth.signInWithGoogleResult();
        error = result.error;
        if (result.redirecting) {
          notice = 'กำลังเปิด Google ในเบราว์เซอร์…';
        } else if (!result.signedIn && result.error == null) {
          notice = 'การเข้าสู่ระบบ Google ยังไม่เสร็จสมบูรณ์ กรุณาลองอีกครั้ง';
        }
      } else {
        error = await _auth.signInWithEmail(_email.text.trim(), _password.text);
      }
    } catch (_) {
      error = 'เชื่อมต่อไม่สำเร็จ ตรวจอินเทอร์เน็ตแล้วลองเข้าสู่ระบบอีกครั้ง';
    }
    if (!mounted) return;
    setState(() {
      _busy = null;
      _error = error;
      _notice = notice;
    });
  }

  void _openAccountForm(Widget screen) {
    if (_busy != null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) => AuthFormLayout(
    title: 'มื้อดี ๆ เริ่มต้นที่นี่',
    subtitle: 'เข้าสู่ระบบเพื่อสั่งมื้อโปรด ติดตามออเดอร์ และบันทึกร้านประจำ',
    showHero: true,
    children: [
      if (widget.connectionError != null) ...[
        AuthNotice(message: widget.connectionError!, isError: true),
        if (widget.onRetryConnection != null)
          TextButton.icon(
            key: const Key('login-retry-connection'),
            onPressed: _busy == null ? widget.onRetryConnection : null,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('เชื่อมต่ออีกครั้ง'),
          ),
        const SizedBox(height: 16),
      ],
      GoogleSignInButton(
        key: const Key('login-google'),
        onPressed: _busy != null ? null : () => _signIn(google: true),
        loading: _busy == 'google',
      ),
      if (_notice != null) ...[
        const SizedBox(height: 16),
        AuthNotice(message: _notice!, isError: false),
      ],
      if (_error != null && _errorIsGoogle) ...[
        const SizedBox(height: 16),
        AuthNotice(message: _error!, isError: true),
      ],
      const SizedBox(height: 20),
      const Row(
        children: [
          Expanded(child: Divider()),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('หรือ', style: TextStyle(color: AppTheme.muted)),
          ),
          Expanded(child: Divider()),
        ],
      ),
      const SizedBox(height: 12),
      AutofillGroup(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const Key('login-email'),
                controller: _email,
                enabled: _busy == null,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [
                  AutofillHints.username,
                  AutofillHints.email,
                ],
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
                key: const Key('login-password'),
                controller: _password,
                enabled: _busy == null,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                autocorrect: false,
                enableSuggestions: false,
                validator: AuthValidation.loginPassword,
                onFieldSubmitted: (_) => _signIn(),
                decoration: InputDecoration(
                  labelText: 'รหัสผ่าน',
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
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _busy != null
                      ? null
                      : () => _openAccountForm(
                          ForgotPasswordScreen(authService: widget.authService),
                        ),
                  child: const Text('ลืมรหัสผ่าน?'),
                ),
              ),
              if (_error != null && !_errorIsGoogle) ...[
                AuthNotice(message: _error!, isError: true),
                const SizedBox(height: 16),
              ],
              FilledButton.icon(
                key: const Key('login-submit'),
                onPressed: _busy != null ? null : () => _signIn(),
                icon: _busy == 'email'
                    ? const AuthProgress()
                    : const Icon(Icons.login_rounded),
                label: Text(
                  _busy == 'email' ? 'กำลังเข้าสู่ระบบ…' : 'เข้าสู่ระบบ',
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('ยังไม่มีบัญชี?', style: TextStyle(color: AppTheme.muted)),
          TextButton(
            onPressed: _busy != null
                ? null
                : () => _openAccountForm(
                    RegisterScreen(authService: widget.authService),
                  ),
            child: const Text('สร้างบัญชี'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      const Text(
        'สำหรับลูกค้าและเจ้าของร้าน ในบัญชีเดียว',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppTheme.muted, fontSize: 12),
      ),
    ],
  );
}
