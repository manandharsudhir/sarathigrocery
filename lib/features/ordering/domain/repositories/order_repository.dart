import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/customer_order.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/delivery_type.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_item.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_status.dart';

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
  });

  void setStatus(CustomerOrder order, OrderStatus status);
}
