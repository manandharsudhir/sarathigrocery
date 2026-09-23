import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/delivery_type.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_item.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_status.dart';

class CustomerOrder {
  CustomerOrder({
    required this.id,
    required this.customer,
    required this.items,
    required this.deliveryType,
    this.discountPercent = 0,
    this.address = '',
    this.notes = '',
    this.status = OrderStatus.placed,
    required this.createdDate,
    required this.updatedDate,
    this.paid = false,
  });

  final String id;
  final Customer customer;
  final List<OrderItem> items;
  final double discountPercent;
  final DeliveryType deliveryType;
  final String address;
  final String notes;
  OrderStatus status;
  final DateTime createdDate;
  DateTime updatedDate;
  bool paid;

  double get subtotal => items.fold(0.0, (sum, i) => sum + i.lineTotal);
  double get total => subtotal - subtotal * discountPercent / 100;
}
