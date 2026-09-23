import 'package:flutter/foundation.dart';

import 'package:sarathigrocery/core/data/remote_store.dart';
import 'package:sarathigrocery/core/services/app_signal.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/user_repository.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';
import 'package:sarathigrocery/features/customers/domain/repositories/customer_repository.dart';
import 'package:sarathigrocery/features/customers/domain/repositories/payment_repository.dart';
import 'package:sarathigrocery/features/customers/domain/usecases/record_payment.dart';
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
import 'package:sarathigrocery/features/sales/domain/repositories/sale_repository.dart';

class OrderingController extends ChangeNotifier {
  OrderingController(
    this._repository,
    ProductRepository products,
    SaleRepository sales,
    CustomerRepository customers,
    this._audit,
    NotificationRepository notifications,
    this._users,
    this._recordPayment,
    this._payments,
    this._commit,
  )   : _placeOrder = PlaceOrder(_repository, products, _audit, notifications),
        _advanceStatus = AdvanceOrderStatus(_repository, products, sales, customers, _audit, notifications, _users),
        _notifications = notifications;

  final OrderRepository _repository;
  final AuditRepository _audit;
  final UserRepository _users;
  final NotificationRepository _notifications;
  final PlaceOrder _placeOrder;
  final AdvanceOrderStatus _advanceStatus;
  final RecordPayment _recordPayment;
  final PaymentRepository _payments;

  /// Waits for the backend to accept queued writes (throws if rejected;
  /// with requireOnline, also if the server can't be reached).
  final Future<void> Function({bool requireOnline}) _commit;

  List<CustomerOrder> get orders => _repository.orders;

  List<OrderItem> get cart => _repository.cart;

  int get pendingCount => _repository.pendingCount;

  double get cartTotal => cart.fold(0.0, (sum, i) => sum + i.lineTotal);

  /// Only available on the ordering customer's own device.
  String? deliveryCodeFor(CustomerOrder order) => _repository.deliveryCodeFor(order.id);

  List<CustomerPayment> paymentsFor(CustomerOrder order) => _payments.payments.where((p) => p.orderId == order.id).toList();

  double paidFor(CustomerOrder order) => paymentsFor(order).where((p) => !p.isReversed).fold(0.0, (sum, p) => sum + p.amount);

  double creditExposure(Customer customer) => _placeOrder.creditExposure(customer);

  /// Everyone who can be assigned a delivery.
  List<AppUser> get deliverers => _users.users.where((u) => u.active && u.can(Permission.deliverOrders)).toList();

  List<CustomerOrder> assignedTo(AppUser user) => orders.where((o) => o.assignedToId == user.id).toList();

  void _changed() {
    notifyListeners();
    AppSignal.instance.ping();
  }

  void addToCart(Product product, int qty) {
    _repository.addToCart(product, qty);
    _changed();
  }

  void updateCartQty(OrderItem item, int qty) {
    _repository.updateCartQty(item, qty);
    _changed();
  }

  void clearCart() {
    _repository.clearCart();
    _changed();
  }

  CustomerOrder? placeOrder(Customer customer, {required DeliveryType deliveryType, String address = '', String notes = '', required String userName, String? userId}) {
    final order = _placeOrder(customer, deliveryType: deliveryType, address: address, notes: notes, userName: userName, userId: userId);
    if (order != null) _changed();
    return order;
  }

  void repeatOrder(CustomerOrder order) {
    for (final item in order.items) {
      _repository.addToCart(item.product, item.qty);
    }
    _changed();
  }

  void advanceOrderStatus(CustomerOrder order, OrderStatus newStatus, {required String userName, String? userId}) {
    _advanceStatus(order, newStatus, userName: userName, userId: userId);
    _changed();
  }

  void assign(CustomerOrder order, AppUser? deliverer, {required AppUser by}) {
    _repository.assign(order, userId: deliverer?.id, userName: deliverer?.name ?? '');
    _audit.record(by.name, 'Delivery assigned', 'Order', entityId: order.id, newValue: deliverer?.name ?? 'unassigned');
    if (deliverer != null && deliverer.id != by.id) {
      _notifications.notify('Delivery assigned', 'Order ${order.id} for ${order.customer.name}${order.address.isEmpty ? '' : ' · ${order.address}'}', userId: deliverer.id);
    }
    _changed();
  }

  /// Delivered before delivery started billing customers — never invoiced.
  List<CustomerOrder> get uninvoicedDeliveries => _advanceStatus.uninvoiced();

  /// Owner: bill those orders onto their customers' balances now.
  int invoiceUninvoicedDeliveries({required AppUser by}) {
    final orders = uninvoicedDeliveries;
    for (final o in orders) {
      _advanceStatus.invoice(o, userName: by.name, userId: by.id);
    }
    _changed();
    return orders.length;
  }

  /// Owner unlocks an order locked by too many wrong delivery codes.
  void resetCodeAttempts(CustomerOrder order, {required AppUser by}) {
    _repository.resetCodeAttempts(order);
    _audit.record(by.name, 'Delivery code attempts reset', 'Order', entityId: order.id);
    _changed();
  }

  Future<int> codeAttempts(CustomerOrder order) => _repository.codeAttempts(order);

  Future<void> _commitOnline(String whatFailed, {bool showDetail = false}) async {
    try {
      await _commit(requireOnline: true);
    } on OfflineException {
      _changed();
      throw PaymentException('No internet connection. Nothing was recorded — connect and try again.');
    } catch (e) {
      _changed();
      // The full error is already reported (Crashlytics); a short hint helps support.
      throw PaymentException(showDetail ? '$whatFailed\n(${e.toString().split('\n').first})' : whatFailed);
    }
  }

  /// Marks [order] delivered (invoicing it onto the customer's balance) and,
  /// if [amount] > 0, records what the customer paid at the door — one
  /// atomic write that must reach the server immediately (a delivery is
  /// never recorded offline). Throws [PaymentException] otherwise; then
  /// nothing is saved and the local copy is rolled back.
  ///
  /// A [deliveryCode] is checked by the server only (the collector can't
  /// read it). Each code tried is first registered as an attempt; after
  /// [kMaxDeliveryCodeAttempts] wrong ones the order is locked until the
  /// owner resets it (or deliver without a code — the customer then
  /// confirms in their app).
  Future<CustomerPayment?> deliverAndCollect(
    CustomerOrder order, {
    required double amount,
    required PaymentMethod method,
    String reference = '',
    String? deliveryCode,
    required AppUser collector,
  }) async {
    if (order.status == OrderStatus.delivered || order.status == OrderStatus.cancelled) throw PaymentException('This order is already closed.');
    if (amount < 0) throw PaymentException('Amount cannot be negative.');
    if (amount > 0 && method != PaymentMethod.cash && reference.trim().isEmpty) {
      throw PaymentException('Enter the ${paymentMethodLabel(method)} reference so it can be verified.');
    }
    final code = amount > 0 ? (deliveryCode ?? '').trim() : '';

    // The backend lets only the assigned deliverer check codes and invoice.
    // Owner/employee delivering an order themselves take it over first.
    if (order.assignedToId != collector.id) {
      if (!collector.can(Permission.recordPayments) || collector.role == UserRole.delivery) {
        throw PaymentException('This order is not assigned to you.');
      }
      assign(order, collector, by: collector);
      await _commitOnline('Could not assign this delivery to you. Try again.', showDetail: true);
    }

    if (code.isNotEmpty) {
      final attempts = await _repository.codeAttempts(order);
      if (attempts >= kMaxDeliveryCodeAttempts) {
        throw PaymentException('Too many wrong codes for this order. Ask the owner to unlock it, or deliver without a code and the customer confirms in their app.');
      }
      final left = kMaxDeliveryCodeAttempts - attempts - 1;
      _repository.registerCodeAttempt(order, code, attempts + 1);
      await _commitOnline('Could not check the code. Try again.', showDetail: true);
      _repository.claimCodeVerified(order);
      await _commitOnline('Wrong delivery code — nothing was recorded. $left ${left == 1 ? 'attempt' : 'attempts'} left. '
          'Ask the customer to check the code on the order in their app. If the order has no code (placed before codes existed), leave the code empty.');
    }

    _advanceStatus(order, OrderStatus.delivered, userName: collector.name, userId: collector.id);
    final payment = amount > 0
        ? _recordPayment(order.customer, amount, method: method, reference: reference, order: order, deliveryCode: code.isEmpty ? null : code, collector: collector)
        : null;
    _changed();
    await _commitOnline('The server refused this delivery. Nothing was recorded.', showDetail: true);
    return payment;
  }
}
