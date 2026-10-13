import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';

String money(num value) => '฿${NumberFormat('#,##0.##').format(value)}';

class ContentWidth extends StatelessWidget {
  final Widget child;
  const ContentWidth({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1000),
      child: child,
    ),
  );
}

class StatePanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? action;
  final VoidCallback? onAction;
  const StatePanel({
    super.key,
    this.icon = Icons.search_rounded,
    required this.title,
    required this.message,
    this.action,
    this.onAction,
  });
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 38,
            backgroundColor: const Color(0xFFFFEEE7),
            child: Icon(icon, color: AppTheme.orange, size: 32),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.muted),
          ),
          if (action != null) ...[
            const SizedBox(height: 18),
            OutlinedButton(onPressed: onAction, child: Text(action!)),
          ],
        ],
      ),
    ),
  );
}

class StatusPill extends StatelessWidget {
  final String label;
  final bool positive;
  const StatusPill(this.label, {super.key, this.positive = true});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: positive ? const Color(0xFFE7F5EE) : const Color(0xFFF1F2F4),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: positive ? AppTheme.green : AppTheme.muted,
      ),
    ),
  );
}
