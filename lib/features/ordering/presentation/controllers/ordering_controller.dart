import 'package:flutter/foundation.dart';

import 'package:sarathigrocery/core/data/remote_store.dart';
import 'package:sarathigrocery/core/services/app_signal.dart';
import 'package:sarathigrocery/features/accounting/domain/books.dart';
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
import 'package:sarathigrocery/features/inventory/domain/repositories/product_repository.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/customer_order.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/delivery_type.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_item.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_status.dart';
import 'package:sarathigrocery/features/ordering/domain/repositories/order_repository.dart';
import 'package:sarathigrocery/features/ordering/domain/usecases/advance_order_status.dart';
import 'package:sarathigrocery/features/ordering/domain/usecases/place_order.dart';
import 'package:sarathigrocery/features/sales/data/bill_numbers.dart';
import 'package:sarathigrocery/features/sales/domain/entities/vat.dart';
import 'package:sarathigrocery/features/sales/domain/repositories/sale_repository.dart';
import 'package:sarathigrocery/features/settings/domain/entities/business_settings.dart';

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
    this._businessName,
    this._guards,
    Books books, {
    VatTerms? Function()? vat,
    BillNumbers? billNumbers,
  })  : _vat = vat ?? (() => null),
        _numbers = billNumbers,
        _placeOrder = PlaceOrder(_repository, products, _audit, notifications),
        _advanceStatus = AdvanceOrderStatus(_repository, products, sales, customers, _audit, books, notifications),
        _notifications = notifications;

  final OrderRepository _repository;
  final AuditRepository _audit;
  final UserRepository _users;
  final NotificationRepository _notifications;
  final PlaceOrder _placeOrder;
  final VatTerms? Function() _vat;
  final BillNumbers? _numbers;

  /// VAT-registered shops (orders carry VAT; delivering issues a tax invoice).
  VatTerms? get vatTerms => _vat();
  final AdvanceOrderStatus _advanceStatus;
  final RecordPayment _recordPayment;
  final PaymentRepository _payments;

  final String Function() _businessName;
  final bool Function(Safeguard) _guards;

  /// Deliver & Collect asks for the customer's signature.
  bool get signatureRequired => _guards(Safeguard.signature);

  /// For shareable receipts.
  String get businessName => _businessName();

  /// Waits for the backend to accept queued writes (throws if rejected;
  /// with requireOnline, also if the server can't be reached).
  final Future<void> Function({bool requireOnline}) _commit;

  List<CustomerOrder> get orders => _repository.orders;

  int get pendingCount => _repository.pendingCount;

  List<CustomerPayment> paymentsFor(CustomerOrder order) => _payments.payments.where((p) => p.orderId == order.id).toList();

  double paidFor(CustomerOrder order) => paymentsFor(order).where((p) => !p.isReversed).fold(0.0, (sum, p) => sum + p.amount);


  /// Everyone who can be assigned a delivery.
  List<AppUser> get deliverers => _users.users.where((u) => u.active && u.can(Permission.deliverOrders)).toList();

  List<CustomerOrder> assignedTo(AppUser user) => orders.where((o) => o.assignedToId == user.id).toList();

  void _changed() {
    notifyListeners();
    AppSignal.instance.ping();
  }

  /// Staff take a phone/WhatsApp order for [customer]. Throws
  /// [BelowMinimumPriceException] for an underpriced line (see [PlaceOrder]).
  CustomerOrder? placeOrderFor(Customer customer, List<OrderItem> items, {required DeliveryType deliveryType, String address = '', String notes = '', required AppUser staff}) {
    if (!staff.can(Permission.createSales)) throw PaymentException('You are not allowed to take orders.');
    final order = _placeOrder(
      customer,
      [for (final i in items) if (i.qty > 0) i],
      deliveryType: deliveryType,
      address: address,
      notes: notes,
      staffName: staff.name,
      allowBelowMinimum: staff.can(Permission.sellBelowMinimum),
      vat: _vat(),
    );
    _changed();
    return order;
  }

  void advanceOrderStatus(CustomerOrder order, OrderStatus newStatus, {required String userName, String? userId}) {
    _advanceStatus(order, newStatus, userName: userName, userId: userId, vatShop: _vat() != null);
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
  /// atomic batch. With [Safeguard.onlineOnly] it must reach the server now
  /// (throws [PaymentException] otherwise; nothing is saved and the local
  /// copy is rolled back); without, it is queued like any other write.
  ///
  /// The customer's [signature] proves the handover (and the payment);
  /// required with [Safeguard.signature].
  Future<CustomerPayment?> deliverAndCollect(
    CustomerOrder order, {
    required double amount,
    required PaymentMethod method,
    String reference = '',
    String? signature,
    String signedName = '',
    required AppUser collector,
  }) async {
    if (order.status == OrderStatus.delivered || order.status == OrderStatus.cancelled) throw PaymentException('This order is already closed.');
    if (amount < 0) throw PaymentException('Amount cannot be negative.');
    if (amount > 0 && method != PaymentMethod.cash && reference.trim().isEmpty) {
      throw PaymentException('Enter the ${paymentMethodLabel(method)} reference so it can be verified.');
    }
    if (signature == null && signatureRequired) {
      throw PaymentException('Ask ${order.customer.name} to sign for the goods${amount > 0 ? ' and the payment' : ''}.');
    }
    if (signature != null && signedName.trim().isEmpty) throw PaymentException('Enter the name of the person who signed.');

    if (order.assignedToId != collector.id && (!collector.can(Permission.recordPayments) || collector.role == UserRole.delivery)) {
      throw PaymentException('This order is not assigned to you.');
    }
    final vatShop = _vat() != null;

    // One synchronous turn = one atomic batch (see CLAUDE.md).
    CustomerPayment? deliver(BillNumber? bill) {
      // The backend lets only the assigned deliverer invoice.
      // Owner/employee delivering an order themselves take it over (same batch).
      if (order.assignedToId != collector.id) assign(order, collector, by: collector);
      if (signature != null) _repository.recordReceipt(order, signature: signature, receivedBy: signedName.trim());
      _advanceStatus(order, OrderStatus.delivered, userName: collector.name, userId: collector.id, bill: bill, vatShop: vatShop, paidNow: amount);
      if (bill != null) _numbers!.take(bill);
      final payment = amount > 0
          ? _recordPayment(order.customer, amount,
              method: method, reference: reference, order: order, signature: signature, signedName: signedName, collector: collector)
          : null;
      _changed();
      return payment;
    }

    if (!vatShop) {
      final payment = deliver(null);
      if (_guards(Safeguard.onlineOnly)) await _commitOnline('The server refused this delivery. Nothing was recorded.', showDetail: true);
      return payment;
    }
    // VAT shop: the delivery issues a numbered tax invoice, so it must reach
    // the server now; retried if another device took the number first.
    for (var attempt = 1;; attempt++) {
      final BillNumber bill;
      try {
        bill = await _numbers!.next('invoice', DateTime.now());
      } catch (_) {
        throw PaymentException('No internet connection: a tax invoice needs the server. Nothing was recorded.');
      }
      final payment = deliver(bill);
      try {
        await _commit(requireOnline: true);
        return payment;
      } on OfflineException {
        _changed();
        throw PaymentException('No internet connection: a tax invoice needs the server. Nothing was recorded.');
      } catch (_) {
        _changed();
        if (attempt == 3) throw PaymentException('Could not issue the invoice. Nothing was recorded — try again.');
      }
    }
  }
}
