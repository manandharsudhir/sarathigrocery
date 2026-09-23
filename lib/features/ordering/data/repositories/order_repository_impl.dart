import 'package:sarathigrocery/core/data/synced_collection.dart';
import 'package:sarathigrocery/core/utils/id_generator.dart';
import 'package:sarathigrocery/features/customers/data/repositories/customer_repository_impl.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/inventory/data/repositories/product_repository_impl.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/customer_order.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/delivery_type.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_item.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_status.dart';
import 'package:sarathigrocery/features/ordering/domain/repositories/order_repository.dart';

class OrderRepositoryImpl implements OrderRepository {
  OrderRepositoryImpl(ProductRepositoryImpl products, CustomerRepositoryImpl customers)
      : _orders = SyncedCollection<CustomerOrder>(
          'orders',
          idOf: (o) => o.id,
          toJson: (o) => {
            'customerId': o.customer.id,
            'items': [for (final i in o.items) {'productId': i.product.id, 'qty': i.qty, 'price': i.price}],
            'discountPercent': o.discountPercent,
            'deliveryType': o.deliveryType.name,
            'address': o.address,
            'notes': o.notes,
            'status': o.status.name,
            'createdDate': toMillis(o.createdDate),
            'updatedDate': toMillis(o.updatedDate),
            'paid': o.paid,
          },
          fromJson: (j) {
            final customer = customers.byId(j['customerId']);
            if (customer == null) return null;
            final items = <OrderItem>[];
            for (final i in (j['items'] as List? ?? const [])) {
              final product = products.byId(i['productId']);
              if (product == null) return null;
              items.add(OrderItem(product: product, qty: toInt(i['qty']), price: toDouble(i['price'])));
            }
            return CustomerOrder(
              id: j['id'],
              customer: customer,
              items: items,
              discountPercent: toDouble(j['discountPercent']),
              deliveryType: DeliveryType.values.byName(j['deliveryType']),
              address: j['address'] ?? '',
              notes: j['notes'] ?? '',
              status: OrderStatus.values.byName(j['status']),
              createdDate: fromMillis(j['createdDate']),
              updatedDate: fromMillis(j['updatedDate']),
              paid: j['paid'] ?? false,
            );
          },
          merge: (o, j) => o
            ..status = OrderStatus.values.byName(j['status'])
            ..updatedDate = fromMillis(j['updatedDate'])
            ..paid = j['paid'] ?? false,
        );

  final SyncedCollection<CustomerOrder> _orders;

  List<SyncedCollection<Object?>> get collections => [_orders];

  @override
  List<CustomerOrder> get orders => _orders.items;

  /// Device-local on purpose: a cart is a draft, not business data.
  @override
  final List<OrderItem> cart = [];

  @override
  int get pendingCount => orders.where((o) => o.status != OrderStatus.delivered && o.status != OrderStatus.cancelled).length;

  @override
  void addToCart(Product product, int qty) {
    for (final item in cart) {
      if (item.product.id == product.id) {
        item.qty += qty;
        return;
      }
    }
    cart.add(OrderItem(product: product, qty: qty, price: product.unitPrice));
  }

  @override
  void updateCartQty(OrderItem item, int qty) {
    if (qty <= 0) {
      cart.remove(item);
    } else {
      item.qty = qty;
    }
  }

  @override
  void clearCart() => cart.clear();

  @override
  CustomerOrder createOrder({
    required Customer customer,
    required List<OrderItem> items,
    required double discountPercent,
    required DeliveryType deliveryType,
    required String address,
    required String notes,
  }) {
    final order = CustomerOrder(
      id: nextId('O'),
      customer: customer,
      items: items,
      discountPercent: discountPercent,
      deliveryType: deliveryType,
      address: address,
      notes: notes,
      createdDate: DateTime.now(),
      updatedDate: DateTime.now(),
    );
    _orders.add(order);
    return order;
  }

  @override
  void setStatus(CustomerOrder order, OrderStatus status) {
    order.status = status;
    order.updatedDate = DateTime.now();
    _orders.save(order);
  }
}
