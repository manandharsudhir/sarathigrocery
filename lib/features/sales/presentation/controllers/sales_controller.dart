import 'package:flutter/foundation.dart';

import 'package:sarathigrocery/core/services/app_signal.dart';
import 'package:sarathigrocery/features/accounting/domain/books.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/cash/domain/repositories/cash_repository.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/customers/domain/repositories/customer_repository.dart';
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
  })  : _moneyAccounts = moneyAccounts ?? (() => const ['cash', 'bank', 'wallet']),
        _vat = vat ?? (() => null),
        _numbers = billNumbers,
        _recordSale = RecordSale(_repository, products, customers, cash, audit, notifications, books),
        _reverseSale = ReverseSale(_repository, products, customers, cash, audit, books);

  final SaleRepository _repository;
  final RecordSale _recordSale;
  final ReverseSale _reverseSale;
  final String Function() _businessName;
  final List<String> Function() _moneyAccounts;
  final VatTerms? Function() _vat;
  final BusinessSettings Function()? _settings;

  /// The shop as printed on bills.
  BusinessSettings get seller => _settings?.call() ?? BusinessSettings(businessName: businessName, businessAddress: '', businessPhone: '', defaultLowStockThreshold: 0, taxPercent: 0);

  VatTerms? get vatTerms => _vat();

  CreditNote? creditNoteFor(Sale sale) => _repository.creditNotes.where((n) => n.sale.id == sale.id).firstOrNull;
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
    );
    if (bill != null) _numbers!.take(bill);
    notifyListeners();
    AppSignal.instance.ping();
    return sale;
  }

  /// Takes the next [kind] number and runs [record] with it, saved online
  /// in one batch; retried if another device took the number first.
  Future<T> _numbered<T>(String kind, T Function(BillNumber bill) record) async {
    for (var attempt = 1;; attempt++) {
      final BillNumber bill;
      try {
        bill = await _numbers!.next(kind, DateTime.now());
      } catch (_) {
        throw AccountingException('No internet connection: a VAT bill needs the server. Nothing was recorded.');
      }
      final result = record(bill);
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
  Future<Sale> sell({
    required List<SaleItem> items,
    required bool isCredit,
    Customer? customer,
    required String userName,
    String? userId,
    bool allowBelowMinimum = false,
    String account = 'cash',
  }) async {
    Sale record(BillNumber? bill) => recordSale(
        items: items, isCredit: isCredit, customer: customer, userName: userName, userId: userId, allowBelowMinimum: allowBelowMinimum, account: account, bill: bill);
    if (!issuesTaxInvoices) return record(null);
    return _numbered('invoice', record);
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
