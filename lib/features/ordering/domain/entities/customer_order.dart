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
    this.address = '',
    this.notes = '',
    this.status = OrderStatus.placed,
    required this.createdDate,
    required this.updatedDate,
    this.assignedToId,
    this.assignedToName = '',
    this.placedByStaffName = '',
    this.receivedSignature,
    this.receivedBy = '',
    this.vatAmount = 0,
    this.vatIncluded = true,
    this.exemptAmount = 0,
  });

  final String id;
  final Customer customer;
  final List<OrderItem> items;
  final DeliveryType deliveryType;
  final String address;
  final String notes;
  OrderStatus status;
  final DateTime createdDate;
  DateTime updatedDate;

  /// Who delivers it (a delivery-role user, or any staff with deliverOrders).
  String? assignedToId;
  String assignedToName;

  /// The staff member who took the order (phone/WhatsApp/in person).
  final String placedByStaffName;

  /// Customer's signature and name when the goods were handed over.
  String? receivedSignature;
  String receivedBy;

  /// VAT worked out when the order was placed (prices are fixed then).
  final double vatAmount;
  final bool vatIncluded;
  final double exemptAmount;

  double get linesTotal => items.fold(0.0, (sum, i) => sum + i.lineTotal);
  double get total => linesTotal + (vatIncluded ? 0 : vatAmount);
}
