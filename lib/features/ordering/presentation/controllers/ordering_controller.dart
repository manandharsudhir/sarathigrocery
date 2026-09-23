import 'package:flutter/foundation.dart';

import 'package:sarathigrocery/core/services/app_signal.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/user_repository.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';
import 'package:sarathigrocery/features/inventory/domain/repositories/product_repository.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/customer_order.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/delivery_type.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_item.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_status.dart';
import 'package:sarathigrocery/features/ordering/domain/repositories/order_repository.dart';
import 'package:sarathigrocery/features/ordering/domain/usecases/advance_order_status.dart';
import 'package:sarathigrocery/features/ordering/domain/usecases/place_order.dart';

class OrderingController extends ChangeNotifier {
  OrderingController(
    this._repository,
    ProductRepository products,
    AuditRepository audit,
    NotificationRepository notifications,
    UserRepository users,
  )   : _placeOrder = PlaceOrder(_repository, products, audit, notifications),
        _advanceStatus = AdvanceOrderStatus(_repository, products, audit, notifications, users);

  final OrderRepository _repository;
  final PlaceOrder _placeOrder;
  final AdvanceOrderStatus _advanceStatus;

  List<CustomerOrder> get orders => _repository.orders;

  List<OrderItem> get cart => _repository.cart;

  int get pendingCount => _repository.pendingCount;

  double get cartTotal => cart.fold(0.0, (sum, i) => sum + i.lineTotal);

  void addToCart(Product product, int qty) {
    _repository.addToCart(product, qty);
    notifyListeners();
    AppSignal.instance.ping();
  }

  void updateCartQty(OrderItem item, int qty) {
    _repository.updateCartQty(item, qty);
    notifyListeners();
    AppSignal.instance.ping();
  }

  void clearCart() {
    _repository.clearCart();
    notifyListeners();
    AppSignal.instance.ping();
  }

  CustomerOrder? placeOrder(Customer customer, {required DeliveryType deliveryType, String address = '', String notes = '', required String userName}) {
    final order = _placeOrder(customer, deliveryType: deliveryType, address: address, notes: notes, userName: userName);
    if (order != null) {
      notifyListeners();
      AppSignal.instance.ping();
    }
    return order;
  }

  void repeatOrder(CustomerOrder order) {
    for (final item in order.items) {
      _repository.addToCart(item.product, item.qty);
    }
    notifyListeners();
    AppSignal.instance.ping();
  }

  void advanceOrderStatus(CustomerOrder order, OrderStatus newStatus, {required String userName}) {
    _advanceStatus(order, newStatus, userName: userName);
    notifyListeners();
    AppSignal.instance.ping();
  }
}
