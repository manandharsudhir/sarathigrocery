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
            'placedByUserId': o.placedByUserId,
            'assignedToId': o.assignedToId,
            'assignedToName': o.assignedToName,
            'overCreditLimit': o.overCreditLimit,
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
              placedByUserId: j['placedByUserId'],
              assignedToId: j['assignedToId'],
              assignedToName: j['assignedToName'] ?? '',
              overCreditLimit: j['overCreditLimit'] ?? false,
            );
          },
          merge: (o, j) => o
            ..status = OrderStatus.values.byName(j['status'])
            ..updatedDate = fromMillis(j['updatedDate'])
            ..assignedToId = j['assignedToId']
            ..assignedToName = j['assignedToName'] ?? '',
        );

  final SyncedCollection<CustomerOrder> _orders;

  /// Kept apart from the order so only the customer can read it — the
  /// delivery person must *get* it from the customer. Doc id = order id.
  final _codes = SyncedCollection<({String orderId, String customerId, String code})>(
    'deliveryCodes',
    idOf: (c) => c.orderId,
    toJson: (c) => {'customerId': c.customerId, 'code': c.code},
    fromJson: (j) => (orderId: j['id'] as String, customerId: j['customerId'] as String, code: j['code'] as String),
  );

  /// Never mirrored; read on demand. Doc id = order id.
  final _codeChecks = SyncedCollection<({String orderId, String code, int attempts})>(
    'codeChecks',
    idOf: (c) => c.orderId,
    toJson: (c) => {'lastCode': c.code, 'attempts': c.attempts, 'verified': false},
    fromJson: (j) => (orderId: j['id'] as String, code: j['lastCode'] as String, attempts: toInt(j['attempts'])),
  );

  List<SyncedCollection<Object?>> get collections => [_orders, _codes, _codeChecks];

  @override
  Future<int> codeAttempts(CustomerOrder order) async => toInt((await _codeChecks.fetch(order.id))?['attempts']);

  @override
  void registerCodeAttempt(CustomerOrder order, String code, int attempt) => _codeChecks.add((orderId: order.id, code: code, attempts: attempt));

  @override
  void claimCodeVerified(CustomerOrder order) => _codeChecks.patch(order.id, {'verified': true});

  @override
  void resetCodeAttempts(CustomerOrder order) => _codeChecks.remove((orderId: order.id, code: '', attempts: 0));

  @override
  String? deliveryCodeFor(String orderId) => _codes.byId(orderId)?.code;

  @override
  void saveDeliveryCode(CustomerOrder order, String code) => _codes.add((orderId: order.id, customerId: order.customer.id, code: code));

  @override
  void assign(CustomerOrder order, {required String? userId, required String userName}) {
    order
      ..assignedToId = userId
      ..assignedToName = userName
      ..updatedDate = DateTime.now();
    _orders.save(order);
  }

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
    String? placedByUserId,
    bool overCreditLimit = false,
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
      placedByUserId: placedByUserId,
      overCreditLimit: overCreditLimit,
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
