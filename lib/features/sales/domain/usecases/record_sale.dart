import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/cash/domain/entities/cash_entry_type.dart';
import 'package:sarathigrocery/features/cash/domain/repositories/cash_repository.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/customers/domain/repositories/customer_repository.dart';
import 'package:sarathigrocery/features/inventory/domain/repositories/product_repository.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_constants.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_item.dart';
import 'package:sarathigrocery/features/sales/domain/repositories/sale_repository.dart';

class RecordSale {
  RecordSale(this._sales, this._products, this._customers, this._cash, this._audit, this._notifications);

  final SaleRepository _sales;
  final ProductRepository _products;
  final CustomerRepository _customers;
  final CashRepository _cash;
  final AuditRepository _audit;
  final NotificationRepository _notifications;

  double _total(List<SaleItem> items, double discountPercent) {
    final subtotal = items.fold(0.0, (sum, i) => sum + i.lineTotal);
    return subtotal - subtotal * discountPercent / 100;
  }

  /// Returns the recorded sale; [Sale.flaggedForApproval] tells the caller
  /// whether it needed joint sign-off (discount or credit limit breach).
  Sale call({
    required List<SaleItem> items,
    required double discountPercent,
    required bool isCredit,
    Customer? customer,
    required String userName,
    String? userId,
  }) {
    final needsApproval = discountPercent > kMaxAutoApprovedDiscountPercent ||
        (isCredit && customer != null && customer.outstandingBalance + _total(items, discountPercent) > customer.creditLimit);

    final sale = _sales.record(
      items: items,
      discountPercent: discountPercent,
      isCredit: isCredit,
      customer: customer,
      flaggedForApproval: needsApproval,
      createdByUserId: userId,
      createdByName: userName,
    );

    for (final item in items) {
      final wasLow = item.product.isLowStock;
      _products.decreaseStock(item.product, item.qty);
      if (!wasLow && item.product.isLowStock) {
        _notifications.notify('Low stock: ${item.product.name}', 'Only ${item.product.stockQty} ${item.product.unitLabel} left.', role: UserRole.owner);
        _notifications.notify('Low stock: ${item.product.name}', 'Only ${item.product.stockQty} ${item.product.unitLabel} left.', role: UserRole.employee);
      }
    }

    if (isCredit && customer != null) {
      _customers.applyBalanceChange(customer, sale.total);
    } else {
      _cash.addLedgerEntry(
        type: CashEntryType.sale,
        amount: sale.total,
        note: 'Sale ${sale.id}${customer != null ? ' - ${customer.name}' : ''}',
        reference: sale.id,
      );
    }

    _audit.record(userName, 'Sale recorded', 'Sale', entityId: sale.id, newValue: sale.total.toStringAsFixed(0));

    return sale;
  }
}
