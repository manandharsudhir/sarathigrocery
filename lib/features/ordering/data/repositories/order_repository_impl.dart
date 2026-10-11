import 'package:sarathigrocery/core/data/synced_collection.dart';
import 'package:sarathigrocery/core/utils/id_generator.dart';
import 'package:sarathigrocery/features/customers/data/repositories/customer_repository_impl.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/inventory/data/repositories/product_repository_impl.dart';
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
            'items': [for (final i in o.items) {'productId': i.product.id, 'qty': i.qty, 'price': i.price, 'unit': i.unit, 'size': i.size}],
            'deliveryType': o.deliveryType.name,
            'address': o.address,
            'notes': o.notes,
            'status': o.status.name,
            'createdDate': toMillis(o.createdDate),
            'updatedDate': toMillis(o.updatedDate),
            'assignedToId': o.assignedToId,
            'assignedToName': o.assignedToName,
            'placedByStaffName': o.placedByStaffName,
            'receivedSignature': o.receivedSignature,
            'receivedBy': o.receivedBy,
            'vatAmount': o.vatAmount,
            'vatIncluded': o.vatIncluded,
            'exemptAmount': o.exemptAmount,
          },
          fromJson: (j) {
            final customer = customers.byId(j['customerId']);
            if (customer == null) return null;
            final items = <OrderItem>[];
            for (final i in (j['items'] as List? ?? const [])) {
              final product = products.byId(i['productId']);
              if (product == null) return null;
              items.add(OrderItem(product: product, qty: toDouble(i['qty']), price: toDouble(i['price']), unit: i['unit'], size: i['size'] == null ? 1 : toDouble(i['size'])));
            }
            return CustomerOrder(
              id: j['id'],
              customer: customer,
              items: items,
              deliveryType: DeliveryType.values.byName(j['deliveryType']),
              address: j['address'] ?? '',
              notes: j['notes'] ?? '',
              status: OrderStatus.values.byName(j['status']),
              createdDate: fromMillis(j['createdDate']),
              updatedDate: fromMillis(j['updatedDate']),
              assignedToId: j['assignedToId'],
              assignedToName: j['assignedToName'] ?? '',
              placedByStaffName: j['placedByStaffName'] ?? '',
              receivedSignature: j['receivedSignature'],
              receivedBy: j['receivedBy'] ?? '',
              vatAmount: toDouble(j['vatAmount']),
              vatIncluded: j['vatIncluded'] ?? true,
              exemptAmount: toDouble(j['exemptAmount']),
            );
          },
          merge: (o, j) => o
            ..status = OrderStatus.values.byName(j['status'])
            ..updatedDate = fromMillis(j['updatedDate'])
            ..assignedToId = j['assignedToId']
            ..assignedToName = j['assignedToName'] ?? ''
            ..receivedSignature = j['receivedSignature']
            ..receivedBy = j['receivedBy'] ?? '',
        );

  final SyncedCollection<CustomerOrder> _orders;

  List<SyncedCollection<Object?>> get collections => [_orders];

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

  @override
  int get pendingCount => orders.where((o) => o.status != OrderStatus.delivered && o.status != OrderStatus.cancelled).length;

  @override
  CustomerOrder createOrder({
    required Customer customer,
    required List<OrderItem> items,
    required DeliveryType deliveryType,
    required String address,
    required String notes,
    required String placedByStaffName,
    double vatAmount = 0,
    bool vatIncluded = true,
    double exemptAmount = 0,
  }) {
    final order = CustomerOrder(
      id: nextId('O'),
      customer: customer,
      items: items,
      deliveryType: deliveryType,
      address: address,
      notes: notes,
      createdDate: DateTime.now(),
      updatedDate: DateTime.now(),
      placedByStaffName: placedByStaffName,
      vatAmount: vatAmount,
      vatIncluded: vatIncluded,
      exemptAmount: exemptAmount,
    );
    _orders.add(order);
    return order;
  }

  @override
  void recordReceipt(CustomerOrder order, {required String signature, required String receivedBy}) {
    order
      ..receivedSignature = signature
      ..receivedBy = receivedBy;
    _orders.save(order);
  }

  @override
  void setStatus(CustomerOrder order, OrderStatus status) {
    order.status = status;
    order.updatedDate = DateTime.now();
    _orders.save(order);
  }
}
