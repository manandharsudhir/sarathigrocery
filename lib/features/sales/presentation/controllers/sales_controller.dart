import 'package:flutter/foundation.dart';

import 'package:sarathigrocery/core/services/app_signal.dart';
import 'package:sarathigrocery/features/accounting/domain/books.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/cash/domain/repositories/cash_repository.dart';
import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_statement.dart';
import 'package:sarathigrocery/features/customers/domain/repositories/payment_repository.dart';
import 'package:sarathigrocery/features/customers/domain/usecases/record_payment.dart';
import 'package:sarathigrocery/features/customers/domain/repositories/customer_repository.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';
import 'package:sarathigrocery/features/inventory/domain/repositories/product_repository.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';
import 'package:sarathigrocery/core/data/remote_store.dart';
import 'package:sarathigrocery/features/sales/data/bill_numbers.dart';
import 'package:sarathigrocery/features/sales/domain/entities/credit_note.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale.dart';
import 'package:sarathigrocery/features/sales/domain/entities/vat.dart';
import 'package:sarathigrocery/features/settings/domain/entities/business_settings.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_item.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_status.dart';
import 'package:sarathigrocery/features/sales/domain/repositories/sale_repository.dart';
import 'package:sarathigrocery/features/sales/domain/usecases/record_sale.dart';
import 'package:sarathigrocery/features/sales/domain/usecases/return_items.dart';
import 'package:sarathigrocery/features/sales/domain/usecases/reverse_sale.dart';

class SalesController extends ChangeNotifier {
  SalesController(
    this._repository,
    ProductRepository products,
    CustomerRepository customers,
    CashRepository cash,
    AuditRepository audit,
    NotificationRepository notifications,
    this._businessName,
    Books books, {
    List<String> Function()? moneyAccounts,
    VatTerms? Function()? vat,
    BillNumbers? billNumbers,
    this._commit,
    this._settings,
    this._payments,
    this._recordPayment,
  })  : _moneyAccounts = moneyAccounts ?? (() => const ['cash', 'bank', 'wallet']),
        _vat = vat ?? (() => null),
        _numbers = billNumbers,
        _recordSale = RecordSale(_repository, products, customers, cash, audit, notifications, books),
        _reverseSale = ReverseSale(_repository, products, customers, cash, audit, books),
        _returnItems = ReturnItems(_repository, products, customers, cash, audit, books),
        _audit = audit;

  final ReturnItems _returnItems;
  final AuditRepository _audit;

  final SaleRepository _repository;
  final RecordSale _recordSale;
  final ReverseSale _reverseSale;
  final String Function() _businessName;
  final List<String> Function() _moneyAccounts;
  final VatTerms? Function() _vat;
  final BusinessSettings Function()? _settings;
  final PaymentRepository? _payments;
  final RecordPayment? _recordPayment;

  /// The shop as printed on bills.
  BusinessSettings get seller => _settings?.call() ?? BusinessSettings(businessName: businessName, businessAddress: '', businessPhone: '', defaultLowStockThreshold: 0, taxPercent: 0);

  VatTerms? get vatTerms => _vat();

  CreditNote? creditNoteFor(Sale sale) => _repository.creditNotes.where((n) => n.sale.id == sale.id).firstOrNull;

  /// The bill raised when order [orderId] was delivered, if this device has
  /// it (delivery staff don't load sales: only the ones they raised this
  /// session are here).
  Sale? invoiceForOrder(String orderId) => _repository.sales.where((s) => s.orderId == orderId && !s.isDoorReturn && s.status == SaleStatus.completed).lastOrNull;
  final BillNumbers? _numbers;
  final Future<void> Function({bool requireOnline})? _commit;

  /// VAT-registered: every sale is a numbered tax invoice (needs internet).
  bool get issuesTaxInvoices => _vat() != null;

  List<CreditNote> get creditNotes => _repository.creditNotes;

  /// Accounts a paid sale can go into.
  List<String> get moneyAccounts => _moneyAccounts();

  /// The open shop's name, for invoices.
  String get businessName => _businessName();

  List<Sale> get sales => _repository.sales;

  /// What New Sale lists before anything is typed: [customer]'s usual
  /// products first (most often bought), then the shop's best sellers.
  List<Product> suggestedProducts(Customer? customer, {int limit = 40}) {
    final mine = <Product, int>{}, all = <Product, int>{};
    for (final s in sales) {
      if (s.status != SaleStatus.completed || s.isDoorReturn) continue;
      for (final i in s.items) {
        all[i.product] = (all[i.product] ?? 0) + 1;
        if (customer != null && s.customer?.id == customer.id) mine[i.product] = (mine[i.product] ?? 0) + 1;
      }
    }
    List<Product> ranked(Map<Product, int> m) => (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).map((e) => e.key).toList();
    return {...ranked(mine), ...ranked(all)}.take(limit).toList();
  }

  /// Customers of the latest sales, newest first.
  List<Customer> get recentCustomers => {
        for (final s in sales.reversed)
          if (s.customer != null) s.customer!,
      }.take(10).toList();

  /// What [customer] last paid for [product] per [unit], if ever.
  double? lastPrice(Customer customer, Product product, String unit) {
    for (final s in sales.reversed) {
      if (s.customer?.id != customer.id || s.status != SaleStatus.completed || s.isDoorReturn) continue;
      for (final i in s.items) {
        if (i.product.id == product.id && i.unit == unit) return i.unitPrice;
      }
    }
    return null;
  }

  double get todayRevenue => _repository.todayRevenue;

  double get totalRevenue => _repository.totalRevenue;

  double get totalCostOfGoods => _repository.totalCostOfGoods;

  Sale recordSale({
    required List<SaleItem> items,
    required bool isCredit,
    Customer? customer,
    required String userName,
    String? userId,
    bool allowBelowMinimum = false,
    String account = 'cash',
    BillNumber? bill,
    double paidNow = 0,
    Sale? corrects,
  }) {
    final sale = _recordSale(
      items: items,
      isCredit: isCredit,
      customer: customer,
      userName: userName,
      userId: userId,
      allowBelowMinimum: allowBelowMinimum,
      account: account,
      vat: _vat(),
      bill: bill,
      paidNow: paidNow,
      corrects: corrects,
    );
    if (bill != null) _numbers!.take(bill);
    notifyListeners();
    AppSignal.instance.ping();
    return sale;
  }

  /// Takes the next [kind] number and runs [record] with it, saved online
  /// in one batch; retried if another device took the number first.
  Future<T> _numbered<T>(String kind, T Function(BillNumber bill) record) => _numberedAll([kind], (bills) => record(bills.single));

  /// [_numbered] for a batch that takes one number of each of [kinds].
  Future<T> _numberedAll<T>(List<String> kinds, T Function(List<BillNumber> bills) record) async {
    for (var attempt = 1;; attempt++) {
      final List<BillNumber> bills;
      try {
        bills = [for (final kind in kinds) await _numbers!.next(kind, DateTime.now())];
      } catch (_) {
        throw AccountingException('No internet connection: a VAT bill needs the server. Nothing was recorded.');
      }
      final result = record(bills);
      try {
        await _commit!(requireOnline: true);
        return result;
      } on OfflineException {
        notifyListeners();
        throw AccountingException('No internet connection: a VAT bill needs the server. Nothing was recorded.');
      } catch (_) {
        notifyListeners();
        if (attempt == 3) throw AccountingException('Could not issue the bill. Nothing was recorded — try again.');
      }
    }
  }

  /// Records a sale; in a VAT shop as a numbered tax invoice (online).
  /// [paidNow] on an udharo sale: part paid at the counter, recorded as a
  /// payment against the bill in the same batch, so the balance only goes
  /// up by the rest.
  Future<Sale> sell({
    required List<SaleItem> items,
    required bool isCredit,
    Customer? customer,
    required String userName,
    String? userId,
    bool allowBelowMinimum = false,
    String account = 'cash',
    ({double amount, PaymentMethod method, String reference, AppUser collector})? paidNow,
    Sale? corrects,
    String reason = '',
  }) async {
    if (corrects != null) {
      if (!canCorrect(corrects)) throw AccountingException('Only a completed counter sale with nothing returned can be corrected.');
      if (reason.trim().isEmpty) throw AccountingException('Say what was wrong.');
    }
    if (paidNow != null) {
      if (!isCredit || customer == null) throw PaymentException('Only a customer\'s udharo sale can be part paid.');
      if (paidNow.amount <= 0) throw PaymentException('Enter an amount greater than zero.');
      if (!paidNow.collector.can(Permission.recordPayments)) throw PaymentException('You are not allowed to record this payment.');
      if (paidNow.method != PaymentMethod.cash && paidNow.reference.trim().isEmpty) {
        throw PaymentException('Enter the ${paymentMethodLabel(paidNow.method)} reference so it can be verified.');
      }
    }
    // One synchronous turn: sale + payment (+ the cancelled sale it
    // corrects) are one batch. The new sale validates itself before
    // anything is written, so a refused sale leaves nothing half-saved.
    Sale record(BillNumber? bill, BillNumber? note) {
      final sale = recordSale(
          items: items, isCredit: isCredit, customer: customer, userName: userName, userId: userId, allowBelowMinimum: allowBelowMinimum, account: account, bill: bill, paidNow: paidNow?.amount ?? 0, corrects: corrects);
      if (paidNow != null) {
        _recordPayment!(customer!, paidNow.amount, method: paidNow.method, reference: paidNow.reference, sale: sale, collector: paidNow.collector);
      }
      if (corrects != null) {
        _reverseSale(corrects, SaleStatus.cancelled, 'Corrected: ${reason.trim()}', userName: userName, creditNote: note);
        if (note != null) _numbers!.take(note);
        _audit.record(userName, 'Sale corrected', 'Sale', entityId: sale.id, oldValue: corrects.invoiceNumber ?? corrects.id, newValue: reason.trim());
      }
      return sale;
    }

    final invoice = issuesTaxInvoices, credit = corrects?.invoiceNumber != null;
    if (!invoice && !credit) return record(null, null);
    return _numberedAll([if (invoice) 'invoice', if (credit) 'credit'], (b) => record(invoice ? b.first : null, credit ? b.last : null));
  }

  /// How much of udharo bill [sale] is paid off, from the customer's
  /// statement (payments pay their own bill first, then the oldest). Null
  /// for paid or reversed sales. Pass [cache] when asking for many sales.
  double? paidOn(Sale sale, [Map<String, CustomerStatement>? cache]) {
    final customer = sale.customer;
    if (!sale.isCredit || customer == null || sale.status != SaleStatus.completed || sale.isDoorReturn || _payments == null) return null;
    return _statement(customer, cache).paidFor(sale);
  }

  CustomerStatement _statement(Customer customer, Map<String, CustomerStatement>? cache) =>
      (cache ?? {}).putIfAbsent(customer.id, () => buildStatement(customer, sales, _payments!.payments));

  /// Goods refused at the door or brought back against bill [sale]
  /// (positive amount).
  double returnedOn(Sale sale, [Map<String, CustomerStatement>? cache]) {
    final customer = sale.customer;
    if (!sale.isCredit || customer == null || _payments == null) {
      return -sales.where((r) => r.returnOf == sale.id && r.status == SaleStatus.completed).fold(0.0, (sum, r) => sum + r.total);
    }
    return _statement(customer, cache).returnedFor(sale);
  }

  /// Refused-at-the-door records against bill [sale].
  List<Sale> doorReturnsOf(Sale sale) => sales.where((s) => s.returnOf == sale.id).toList();

  /// Collects [amount] against [sale] (paid off first; the rest goes to
  /// older bills, then advance).
  CustomerPayment collect(Sale sale, double amount, {required PaymentMethod method, String reference = '', String? signature, String signedName = '', required AppUser collector}) {
    final payment = _recordPayment!(sale.customer!, amount, method: method, reference: reference, signature: signature, signedName: signedName, sale: sale, collector: collector);
    notifyListeners();
    AppSignal.instance.ping();
    return payment;
  }

  /// Cancel ([SaleStatus.cancelled]) or return a sale; a tax invoice is
  /// reversed by a numbered credit note (online).
  Future<bool> reverse(Sale sale, SaleStatus status, String reason, {required String userName}) async {
    bool run(BillNumber? note) {
      final ok = _reverseSale(sale, status, reason, userName: userName, creditNote: note);
      if (note != null) _numbers!.take(note);
      if (ok) {
        notifyListeners();
        AppSignal.instance.ping();
      }
      return ok;
    }

    if (sale.invoiceNumber == null) return run(null);
    if (sale.status != SaleStatus.completed) return false;
    return _numbered('credit', run);
  }

  /// A counter sale that can be corrected or take items back: completed,
  /// not an order's bill, nothing returned on it yet (for [canCorrect]).
  bool canCorrect(Sale sale) => sale.status == SaleStatus.completed && !sale.isDoorReturn && sale.orderId == null && doorReturnsOf(sale).every((r) => r.status != SaleStatus.completed);

  bool canReturnItems(Sale sale) => sale.status == SaleStatus.completed && !sale.isDoorReturn && sale.orderId == null && _returnItems.remaining(sale).any((q) => q > 1e-9);

  /// What is still on [sale] per line, after items brought back.
  List<double> remainingOn(Sale sale) => _returnItems.remaining(sale);

  /// The sale that replaced [sale], if it was corrected.
  Sale? correctionOf(Sale sale) => sales.where((s) => s.corrects == sale.id).firstOrNull;

  /// Items of counter sale [sale] brought back ([returned]: line index →
  /// quantity in that line's unit): a credit note in a VAT shop (online).
  Future<Sale> returnItems(Sale sale, Map<int, double> returned, String reason, {required String userName, String? userId}) async {
    Sale run(BillNumber? note) {
      final back = _returnItems(sale, returned, reason, userName: userName, userId: userId, vat: _vat(), creditNote: note);
      if (note != null) _numbers!.take(note);
      notifyListeners();
      AppSignal.instance.ping();
      return back;
    }

    if (sale.invoiceNumber == null) return run(null);
    _returnItems.check(sale, returned, reason, vat: _vat(), creditNote: (series: '', seq: 0, number: ''));
    return _numbered('credit', run);
  }

  bool cancelSale(Sale sale, String reason, {required String userName}) {
    final ok = _reverseSale(sale, SaleStatus.cancelled, reason, userName: userName);
    if (ok) {
      notifyListeners();
      AppSignal.instance.ping();
    }
    return ok;
  }

  bool returnSale(Sale sale, String reason, {required String userName}) {
    final ok = _reverseSale(sale, SaleStatus.returned, reason, userName: userName);
    if (ok) {
      notifyListeners();
      AppSignal.instance.ping();
    }
    return ok;
  }
}
