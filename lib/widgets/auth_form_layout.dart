import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A scrollable, keyboard-safe shell shared by all account forms.
class AuthFormLayout extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;
  final bool showBack;
  final bool showHero;

  const AuthFormLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.showBack = false,
    this.showHero = false,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: showBack ? AppBar(title: const Text('บัญชี MSU Food')) : null,
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showHero) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: SizedBox(
                      height: 148,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.asset(
                            'assets/images/rice.jpg',
                            fit: BoxFit.cover,
                          ),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [Color(0xE6182B33), Color(0x20182B33)],
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.all(22),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'GOOD FOOD.\nGOOD DAY.',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  height: 1.15,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                const Text(
                  'MSU FOOD',
                  style: TextStyle(
                    color: AppTheme.accent,
                    letterSpacing: 3,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(title, style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  style: const TextStyle(color: AppTheme.muted, height: 1.7),
                ),
                const SizedBox(height: 24),
                ...children,
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class AuthNotice extends StatelessWidget {
  final String message;
  final bool isError;
  final IconData icon;

  const AuthNotice({
    super.key,
    required this.message,
    this.isError = false,
    this.icon = Icons.info_outline_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final color = isError
        ? Theme.of(context).colorScheme.error
        : AppTheme.green;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: .2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(isError ? Icons.error_outline_rounded : icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: TextStyle(color: color)),
            ),
          ],
        ),
      ),
    );
  }
}

class AuthProgress extends StatelessWidget {
  const AuthProgress({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 20,
    height: 20,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}
