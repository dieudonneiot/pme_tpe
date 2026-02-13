import 'package:flutter/widgets.dart';
import 'cart_service.dart';

class CartScope extends InheritedNotifier<CartService> {
  const CartScope({
    super.key,
    required CartService cart,
    required super.child,
  }) : super(notifier: cart);

  static CartService of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<CartScope>();
    assert(scope != null, 'CartScope not found. Wrap MaterialApp with CartScope.');
    return scope!.notifier!;
  }
}
