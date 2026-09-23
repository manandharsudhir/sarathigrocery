import 'package:flutter/foundation.dart';

import 'package:sarathigrocery/core/services/app_signal.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/cash/domain/repositories/cash_repository.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/customers/domain/repositories/customer_repository.dart';
import 'package:sarathigrocery/features/inventory/domain/repositories/product_repository.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale.dart';
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
  )   : _recordSale = RecordSale(_repository, products, customers, cash, audit, notifications),
        _reverseSale = ReverseSale(_repository, products, customers, cash, audit);

  final SaleRepository _repository;
  final RecordSale _recordSale;
  final ReverseSale _reverseSale;

  List<Sale> get sales => _repository.sales;

  double get todayRevenue => _repository.todayRevenue;

  double get totalRevenue => _repository.totalRevenue;

  double get totalCostOfGoods => _repository.totalCostOfGoods;

  Sale recordSale({
    required List<SaleItem> items,
    required double discountPercent,
    required bool isCredit,
    Customer? customer,
    required String userName,
    String? userId,
  }) {
    final sale = _recordSale(
      items: items,
      discountPercent: discountPercent,
      isCredit: isCredit,
      customer: customer,
      userName: userName,
      userId: userId,
    );
    notifyListeners();
    AppSignal.instance.ping();
    return sale;
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
