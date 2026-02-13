import 'dart:math';
import 'package:flutter/foundation.dart';

class CartBusinessMismatch implements Exception {
  final String currentBusinessId;
  final String incomingBusinessId;
  CartBusinessMismatch(this.currentBusinessId, this.incomingBusinessId);

  @override
  String toString() =>
      'CartBusinessMismatch(current=$currentBusinessId, incoming=$incomingBusinessId)';
}

@immutable
class CartItem {
  final String productId;
  final String businessId;
  final String title;
  final num unitPrice;
  final String currency;
  final String? mediaUrl;
  final int qty;

  const CartItem({
    required this.productId,
    required this.businessId,
    required this.title,
    required this.unitPrice,
    required this.currency,
    this.mediaUrl,
    required this.qty,
  });

  CartItem copyWith({int? qty}) => CartItem(
        productId: productId,
        businessId: businessId,
        title: title,
        unitPrice: unitPrice,
        currency: currency,
        mediaUrl: mediaUrl,
        qty: qty ?? this.qty,
      );

  num get lineTotal => unitPrice * qty;
}

class CartService extends ChangeNotifier {
  String? _businessId;
  String? _currency;
  final Map<String, CartItem> _itemsByProduct = {};

  String? get businessId => _businessId;
  String get currency => _currency ?? 'XOF';

  List<CartItem> get items => _itemsByProduct.values.toList()
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

  int get totalQty => _itemsByProduct.values.fold(0, (s, it) => s + it.qty);
  num get subtotal => _itemsByProduct.values.fold<num>(0, (s, it) => s + it.lineTotal);

  bool get isEmpty => _itemsByProduct.isEmpty;

  void clear() {
    _businessId = null;
    _currency = null;
    _itemsByProduct.clear();
    notifyListeners();
  }

  void add({
    required String productId,
    required String businessId,
    required String title,
    required num unitPrice,
    required String currency,
    String? mediaUrl,
    int qty = 1,
  }) {
    if (_businessId != null && _businessId != businessId) {
      throw CartBusinessMismatch(_businessId!, businessId);
    }

    _businessId ??= businessId;
    _currency ??= currency;

    final existing = _itemsByProduct[productId];
    if (existing == null) {
      _itemsByProduct[productId] = CartItem(
        productId: productId,
        businessId: businessId,
        title: title,
        unitPrice: unitPrice,
        currency: currency,
        mediaUrl: mediaUrl,
        qty: max(1, qty),
      );
    } else {
      _itemsByProduct[productId] = existing.copyWith(qty: existing.qty + max(1, qty));
    }
    notifyListeners();
  }

  void setQty(String productId, int qty) {
    final existing = _itemsByProduct[productId];
    if (existing == null) return;

    if (qty <= 0) {
      _itemsByProduct.remove(productId);
      if (_itemsByProduct.isEmpty) {
        _businessId = null;
        _currency = null;
      }
    } else {
      _itemsByProduct[productId] = existing.copyWith(qty: qty);
    }
    notifyListeners();
  }

  void inc(String productId) {
    final existing = _itemsByProduct[productId];
    if (existing == null) return;
    setQty(productId, existing.qty + 1);
  }

  void dec(String productId) {
    final existing = _itemsByProduct[productId];
    if (existing == null) return;
    setQty(productId, existing.qty - 1);
  }
}
