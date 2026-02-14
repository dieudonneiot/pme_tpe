import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'cart_scope.dart';

import '../../core/widgets/app_back_button.dart';

class CartPage extends StatelessWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = CartScope.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(fallbackPath: '/explore'),
        title: const Text('Panier'),
      ),
      body: AnimatedBuilder(
        animation: cart,
        builder: (context, child) {
          if (cart.isEmpty) {
            return const Center(child: Text('Votre panier est vide.'));
          }

          return Column(
            children: [
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: cart.items.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final it = cart.items[i];
                    return Card(
                      child: ListTile(
                        title: Text(it.title),
                        subtitle: Text('${it.unitPrice} ${it.currency}  •  x${it.qty}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: () => cart.dec(it.productId),
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                            Text('${it.qty}'),
                            IconButton(
                              onPressed: () => cart.inc(it.productId),
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Text('Total', style: TextStyle(fontWeight: FontWeight.w600)),
                          const Spacer(),
                          Text(
                            '${cart.subtotal} ${cart.currency}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: cart.clear,
                              child: const Text('Vider'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => context.push('/checkout'),
                              icon: const Icon(Icons.payment),
                              label: const Text('Payer'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
