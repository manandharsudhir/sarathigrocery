import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/customer_order.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/delivery_type.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_item.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_status.dart';

const kMaxDeliveryCodeAttempts = 5;

abstract class OrderRepository {
  List<CustomerOrder> get orders;

  List<OrderItem> get cart;

  int get pendingCount;

  void addToCart(Product product, int qty);

  void updateCartQty(OrderItem item, int qty);

  void clearCart();

  CustomerOrder createOrder({
    required Customer customer,
    required List<OrderItem> items,
    required double discountPercent,
    required DeliveryType deliveryType,
    required String address,
    required String notes,
    String? placedByUserId,
    bool overCreditLimit,
  });

  /// The code the customer reads out at delivery. Only the customer's own
  /// device can see it (null elsewhere).
  String? deliveryCodeFor(String orderId);

  void saveDeliveryCode(CustomerOrder order, String code);

  /// Wrong-code protection: every code tried for an order must first be
  /// registered as an attempt; the backend caps attempts at
  /// [kMaxDeliveryCodeAttempts] and only accepts a payment quoting the
  /// last registered code.
  Future<int> codeAttempts(CustomerOrder order);

  void registerCodeAttempt(CustomerOrder order, String code, int attempt);

  /// Asks the backend to confirm the last registered code is the real one;
  /// it refuses otherwise (the collector never learns the code itself).
  void claimCodeVerified(CustomerOrder order);

  /// Owner unlocks an order after too many wrong codes.
  void resetCodeAttempts(CustomerOrder order);

  /// [userId] null = unassign.
  void assign(CustomerOrder order, {required String? userId, required String userName});

  void setStatus(CustomerOrder order, OrderStatus status);
}
