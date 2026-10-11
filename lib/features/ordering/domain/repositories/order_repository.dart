import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/customer_order.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/delivery_type.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_item.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_status.dart';

abstract class OrderRepository {
  List<CustomerOrder> get orders;

  int get pendingCount;

  CustomerOrder createOrder({
    required Customer customer,
    required List<OrderItem> items,
    required DeliveryType deliveryType,
    required String address,
    required String notes,
    required String placedByStaffName,
    double vatAmount,
    bool vatIncluded,
    double exemptAmount,
  });

  /// The customer's signature on receiving the goods.
  void recordReceipt(CustomerOrder order, {required String signature, required String receivedBy});

  /// [userId] null = unassign.
  void assign(CustomerOrder order, {required String? userId, required String userName});

  void setStatus(CustomerOrder order, OrderStatus status);
}
