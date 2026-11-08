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
import 'package:sarathigrocery/features/sales/domain/entities/sale.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_status.dart';
import 'package:sarathigrocery/features/sales/domain/repositories/sale_repository.dart';
import 'package:sarathigrocery/features/sales/domain/usecases/reverse_sale.dart';
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
    this._reverseSale,
  })  : _vat = vat ?? (() => null),
        _sales = sales,
        _numbers = billNumbers,
        _placeOrder = PlaceOrder(_repository, products, _audit, notifications),
        _productsRepo = products,
        _advanceStatus = AdvanceOrderStatus(_repository, products, sales, customers, _audit, books, notifications),
        _notifications = notifications;

  final OrderRepository _repository;
  final AuditRepository _audit;
  final UserRepository _users;
  final NotificationRepository _notifications;
  final PlaceOrder _placeOrder;
  final VatTerms? Function() _vat;
  final BillNumbers? _numbers;
  final ReverseSale? _reverseSale;
  final ProductRepository _productsRepo;
  final SaleRepository _sales;

  /// The order's bill (issued at dispatch), if this device can see sales.
  Sale? invoiceFor(CustomerOrder order) => order.invoiceId == null ? null : _sales.sales.where((s) => s.id == order.invoiceId).firstOrNull;

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

  /// Moves [order] on. Going out for delivery bills it: in a VAT shop use
  /// [dispatch] (the tax invoice needs the server).
  void advanceOrderStatus(CustomerOrder order, OrderStatus newStatus, {required String userName, String? userId}) {
    _advanceStatus(order, newStatus, userName: userName, userId: userId, vatShop: _vat() != null, prepaid: paidFor(order));
    _changed();
  }

  /// Sends [order] out for delivery and issues its bill (numbered, online,
  /// in a VAT shop). What's been paid so far is printed on it.
  Future<void> dispatch(CustomerOrder order, {required AppUser by}) async {
    if (order.status == OrderStatus.outForDelivery || order.status == OrderStatus.delivered || order.status == OrderStatus.cancelled) return;
    void run(BillNumber? bill) {
      _advanceStatus(order, OrderStatus.outForDelivery, userName: by.name, userId: by.id, bill: bill, vatShop: bill != null, prepaid: paidFor(order));
      if (bill != null) _numbers!.take(bill);
      _changed();
    }

    if (_vat() == null) return run(null);
    await _numbered('invoice', run, 'No internet connection: a tax invoice needs the server. Nothing was recorded.');
  }

  /// Takes the next [kind] number and runs [record] with it in one batch,
  /// saved online; retried if another device took the number first.
  Future<T> _numbered<T>(String kind, T Function(BillNumber bill) record, String offline) async {
    for (var attempt = 1;; attempt++) {
      final BillNumber bill;
      try {
        bill = await _numbers!.next(kind, DateTime.now());
      } catch (_) {
        throw PaymentException(offline);
      }
      final result = record(bill);
      try {
        await _commit(requireOnline: true);
        return result;
      } on OfflineException {
        _changed();
        throw PaymentException(offline);
      } catch (_) {
        _changed();
        if (attempt == 3) throw PaymentException('Could not issue the bill. Nothing was recorded — try again.');
      }
    }
  }

  /// The goods came back undelivered (customer away or refused it all):
  /// the bill is cancelled (credit note in a VAT shop), the stock is held for
  /// the order again and it goes back to Ready; the next dispatch bills anew.
  Future<void> notDelivered(CustomerOrder order, String reason, {required AppUser by}) async {
    if (order.status != OrderStatus.outForDelivery || order.invoiceId == null) throw PaymentException('Only an order out for delivery with a bill can come back.');
    if (!by.can(Permission.cancelSales)) throw PaymentException('Ask someone who can cancel sales to do this.');
    final sale = invoiceFor(order);
    if (sale == null) throw PaymentException('This order\'s bill isn\'t on this device yet. Try again in a moment.');
    final why = reason.trim().isEmpty ? 'Not delivered' : 'Not delivered: ${reason.trim()}';
    void run(BillNumber? note) {
      _reverseSale!(sale, SaleStatus.cancelled, why, userName: by.name, creditNote: note);
      if (note != null) _numbers!.take(note);
      for (final item in order.items) {
        _productsRepo.reserveStock(item.product, item.baseQty);
      }
      order
        ..invoiceId = null
        ..invoiceNumber = ''
        ..prepaid = 0;
      _repository.setStatus(order, OrderStatus.ready);
      _audit.record(by.name, 'Order not delivered', 'Order', entityId: order.id, oldValue: 'outForDelivery', newValue: why);
      _changed();
    }

    if (sale.invoiceNumber == null) return run(null);
    await _numbered('credit', run, 'No internet connection: a credit note needs the server. Nothing was recorded.');
  }

  /// What refusing [refused] (line index → qty in that line's unit) takes
  /// off [order]'s bill, VAT included.
  double refusedValue(CustomerOrder order, Map<int, double> refused) {
    var lines = 0.0, exempt = 0.0;
    for (final MapEntry(key: i, value: qty) in refused.entries) {
      final value = qty * order.items[i].price;
      lines += value;
      if (order.items[i].product.vatExempt) exempt += value;
    }
    return lines + (order.vatIncluded ? 0 : vatOn(lines - exempt, _vat()));
  }

  /// Money paid for [order] before it goes out (counter, wallet, bank).
  CustomerPayment prepay(CustomerOrder order, double amount, {required PaymentMethod method, String reference = '', required AppUser collector}) {
    if (order.invoiceId != null || order.status == OrderStatus.delivered || order.status == OrderStatus.cancelled) {
      throw PaymentException('This order is already billed: collect against its bill.');
    }
    final payment = _recordPayment(order.customer, amount, method: method, reference: reference, order: order, collector: collector);
    _changed();
    return payment;
  }

  /// The customer-signed shop copy of the bill is back at the shop.
  void markShopCopyReceived(CustomerOrder order, {required AppUser by}) {
    if (!by.can(Permission.reconcileCash)) throw PaymentException('Only cash staff mark the signed copy received.');
    order
      ..shopCopyAt = DateTime.now()
      ..shopCopyByName = by.name;
    _repository.save(order);
    _audit.record(by.name, 'Signed shop copy received', 'Order', entityId: order.id);
    _changed();
  }

  /// Delivered orders whose signed shop copy hasn't come back after a day.
  List<CustomerOrder> get shopCopiesMissing => orders
      .where((o) => o.status == OrderStatus.delivered && o.invoiceId != null && o.shopCopyAt == null && DateTime.now().difference(o.updatedDate).inHours >= 24)
      .toList();

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
  ///
  /// An order billed at dispatch is only marked delivered here; [refused]
  /// (line index → quantity in that line's unit) returns goods the customer
  /// didn't take, against its bill, in the same batch.
  Future<CustomerPayment?> deliverAndCollect(
    CustomerOrder order, {
    required double amount,
    required PaymentMethod method,
    String reference = '',
    String? signature,
    String signedName = '',
    Map<int, double> refused = const {},
    required AppUser collector,
  }) async {
    refused = {for (final e in refused.entries) if (e.value > 0) e.key: e.value};
    if (refused.isNotEmpty && order.invoiceId == null) throw PaymentException('This order wasn\'t billed at dispatch: deliver it in full.');
    if (refused.length == order.items.length && refused.entries.every((e) => e.value >= order.items[e.key].qty - 1e-9)) {
      throw PaymentException('Nothing was accepted: use Not delivered instead.');
    }
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

    if (order.invoiceId != null) {
      // Billed at dispatch: receipt, delivered, refused goods, payment.
      CustomerPayment? handOver(BillNumber? creditNote) {
        if (order.assignedToId != collector.id) assign(order, collector, by: collector);
        if (signature != null) _repository.recordReceipt(order, signature: signature, receivedBy: signedName.trim());
        if (refused.isNotEmpty) _advanceStatus.doorReturn(order, refused, userName: collector.name, userId: collector.id, vat: _vat(), creditNote: creditNote);
        if (creditNote != null) _numbers!.take(creditNote);
        _advanceStatus(order, OrderStatus.delivered, userName: collector.name, userId: collector.id, vatShop: vatShop);
        final payment = amount > 0
            ? _recordPayment(order.customer, amount,
                method: method, reference: reference, order: order, signature: signature, signedName: signedName, collector: collector)
            : null;
        _changed();
        return payment;
      }

      if (refused.isNotEmpty && vatShop) {
        return _numbered('credit', handOver, 'No internet connection: refused goods on a tax invoice need a credit note from the server. Nothing was recorded.');
      }
      final payment = handOver(null);
      if (_guards(Safeguard.onlineOnly)) await _commitOnline('The server refused this delivery. Nothing was recorded.', showDetail: true);
      return payment;
    }

    // Not billed yet (went out before dispatch billing): bill it now.
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
