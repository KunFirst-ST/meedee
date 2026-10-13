import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/auth_gate.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';
import 'widgets/food_ui.dart';

Future<void> _initializeApi() => AuthService.instance.initialize();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var ready = false;
  String? connectionError;
  try {
    await _initializeApi();
    ready = true;
  } catch (error) {
    connectionError = _connectionMessage(error);
    debugPrint('MSU Food account connection is unavailable.');
  }
  runApp(MsuFoodApp(apiReady: ready, connectionError: connectionError));
}

String _connectionMessage(Object error) => error is ApiException
    ? error.message
    : 'เชื่อมต่อระบบบัญชีไม่ได้ ตรวจอินเทอร์เน็ตแล้วลองอีกครั้ง';

/// Only a connected API session can expose account and business screens.
class MsuFoodApp extends StatefulWidget {
  final bool apiReady;
  final AuthService? authService;
  final Future<void> Function()? initializeApi;
  final String? connectionError;

  const MsuFoodApp({
    super.key,
    this.apiReady = false,
    this.authService,
    this.initializeApi,
    this.connectionError,
  });

  @override
  State<MsuFoodApp> createState() => _MsuFoodAppState();
}

class _MsuFoodAppState extends State<MsuFoodApp> {
  final _navigator = GlobalKey<NavigatorState>();
  StreamSubscription? _sessions;
  late bool _ready = widget.apiReady;
  late String _error =
      widget.connectionError ??
      'ระบบบัญชียังไม่เชื่อมต่อ กรุณาลองอีกครั้งหรือติดต่อผู้ดูแลแอป';
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    _sessions = (widget.authService ?? AuthService.instance).userChanges.listen(
      (user) {
        if (user == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _navigator.currentState?.popUntil((route) => route.isFirst);
            }
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _sessions?.cancel();
    super.dispose();
  }

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await (widget.initializeApi ?? _initializeApi)();
      if (mounted) setState(() => _ready = true);
    } catch (error) {
      if (mounted) setState(() => _error = _connectionMessage(error));
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: _navigator,
    initialRoute: '/',
    title: 'MSU Food',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('th'), Locale('en')],
    locale: const Locale('th'),
    home: _ready
        ? AuthGate(authService: widget.authService)
        : Stack(
            children: [
              AbsorbPointer(
                absorbing: _retrying,
                child: Scaffold(
                  body: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 500),
                      child: StatePanel(
                        title: 'ระบบบัญชียังไม่พร้อมใช้งาน',
                        message: _error,
                        action: 'เชื่อมต่ออีกครั้ง',
                        onAction: _retry,
                      ),
                    ),
                  ),
                ),
              ),
              if (_retrying)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(child: LinearProgressIndicator()),
                ),
            ],
          ),
  );
}
