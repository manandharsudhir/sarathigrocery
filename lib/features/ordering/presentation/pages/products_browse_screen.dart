import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';
import 'package:sarathigrocery/features/inventory/presentation/controllers/inventory_controller.dart';
import 'package:sarathigrocery/features/ordering/presentation/controllers/ordering_controller.dart';

class ProductsBrowseScreen extends StatefulWidget {
  const ProductsBrowseScreen({super.key, required this.inventory, required this.ordering, this.onOpenCart});

  final InventoryController inventory;
  final OrderingController ordering;
  final VoidCallback? onOpenCart;

  @override
  State<ProductsBrowseScreen> createState() => _ProductsBrowseScreenState();
}

class _ProductsBrowseScreenState extends State<ProductsBrowseScreen> {
  String _query = '';
  String? _category;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.inventory, widget.ordering]),
      builder: (context, _) {
        final products = widget.inventory.products.where((p) {
          if (!p.isActive) return false;
          if (_category != null && p.category != _category) return false;
          if (_query.isNotEmpty && !p.name.toLowerCase().contains(_query.toLowerCase())) return false;
          return true;
        }).toList();

        final cartCount = widget.ordering.cart.fold<int>(0, (sum, i) => sum + i.qty);

        return Scaffold(
          appBar: AppBar(title: const Text('Products')),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search products', isDense: true, border: OutlineInputBorder()),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(label: const Text('All'), selected: _category == null, onSelected: (_) => setState(() => _category = null)),
                    ),
                    ...widget.inventory.categories.map((c) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(label: Text(c), selected: _category == c, onSelected: (_) => setState(() => _category = c)),
                        )),
                  ],
                ),
              ),
              Expanded(
                child: products.isEmpty
                    ? const Center(child: Text('No products match your search.'))
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(16, 16, 16, cartCount > 0 ? 96 : 16),
                        itemCount: products.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) => _ProductRow(
                          product: products[index],
                          ordering: widget.ordering,
                        ),
                      ),
              ),
            ],
          ),
          // Only appears once there's something to check out — keeps the
          // browsing screen clean until it's useful.
          floatingActionButton: cartCount == 0 || widget.onOpenCart == null
              ? null
              : FloatingActionButton.extended(heroTag: null, 
                  onPressed: widget.onOpenCart,
                  icon: const Icon(Icons.shopping_cart),
                  label: Text('View cart ($cartCount) · ${formatNpr(widget.ordering.cartTotal)}'),
                ),
        );
      },
    );
  }
}

/// Shows a plain "Add" until the item is in the cart, then becomes a stepper
/// — so changing your mind about quantity never means a trip to the cart.
class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product, required this.ordering});

  final Product product;
  final OrderingController ordering;

  @override
  Widget build(BuildContext context) {
    final inCart = ordering.cart.where((i) => i.product.id == product.id).toList();
    final qty = inCart.isEmpty ? 0 : inCart.first.qty;
    final outOfStock = product.availableStock <= 0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Theme.of(context).dividerColor)),
      child: ListTile(
        title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          outOfStock
              ? '${formatNpr(product.unitPrice)} / ${product.unitLabel} · Out of stock'
              : '${formatNpr(product.unitPrice)} / ${product.unitLabel} · ${product.availableStock} available',
          style: outOfStock ? const TextStyle(color: Colors.red) : null,
        ),
        trailing: qty == 0
            ? FilledButton(
                onPressed: outOfStock ? null : () => ordering.addToCart(product, 1),
                child: const Text('Add'),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => ordering.updateCartQty(inCart.first, qty - 1),
                  ),
                  SizedBox(width: 24, child: Text('$qty', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: qty < product.availableStock ? () => ordering.updateCartQty(inCart.first, qty + 1) : null,
                  ),
                ],
              ),
      ),
    );
  }
}
