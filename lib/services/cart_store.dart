import 'package:flutter/foundation.dart';
import 'dart:math';

/// Session-only drafts are scoped by account and restaurant.
class CartDraft extends ChangeNotifier {
  static final _random = Random.secure();
  static String _newRequestId() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  String requestId = _newRequestId();
  final Map<String, int> _quantities = {};
  String note = '';
  Map<String, int> get quantities => Map.unmodifiable(_quantities);
  int get count => _quantities.values.fold(0, (a, b) => a + b);
  int quantity(String id) => _quantities[id] ?? 0;
  void setQuantity(String id, int value) {
    if (value < 0 || value > 20) return;
    if (value == 0) {
      _quantities.remove(id);
    } else {
      _quantities[id] = value;
    }
    notifyListeners();
  }

  void clear() {
    _quantities.clear();
    note = '';
    requestId = _newRequestId();
    notifyListeners();
  }
}

class CartStore {
  static final Map<String, CartDraft> _drafts = {};
  static CartDraft forShop(String account, String shop) =>
      _drafts.putIfAbsent('$account/$shop', CartDraft.new);
  static void remove(String account, String shop) {
    _drafts.remove('$account/$shop');
  }

  static void clearAccount(String account) {
    _drafts.removeWhere((key, _) => key.startsWith('$account/'));
  }
}
