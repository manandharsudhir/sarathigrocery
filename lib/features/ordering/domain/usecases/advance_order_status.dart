import 'package:sarathigrocery/features/accounting/domain/books.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';
import 'package:sarathigrocery/features/customers/domain/repositories/customer_repository.dart';
import 'package:sarathigrocery/features/inventory/domain/repositories/product_repository.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/customer_order.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_status.dart';
import 'package:sarathigrocery/features/ordering/domain/repositories/order_repository.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_item.dart';
import 'package:sarathigrocery/features/sales/domain/entities/vat.dart';
import 'package:sarathigrocery/features/sales/domain/repositories/sale_repository.dart';

/// Advances (or cancels) an order. Cancelling releases reserved stock.
/// Going out for delivery bills it: the reservation becomes a stock
/// deduction and an invoice (credit sale linked to the order) goes onto the
/// customer's balance, so the printed bill travels with the goods. Whatever
/// they pay is then recorded as a payment against that balance. Orders that
/// went out before dispatch billing are billed on delivery instead.
class AdvanceOrderStatus {
  AdvanceOrderStatus(this._orders, this._products, this._sales, this._customers, this._audit, this._books, this._notifications);

  final OrderRepository _orders;
  final ProductRepository _products;
  final SaleRepository _sales;
  final CustomerRepository _customers;
  final AuditRepository _audit;
  final Books _books;
  final NotificationRepository _notifications;

  /// Billing in a VAT shop issues a tax invoice: [bill] is its number.
  /// [paidNow]: paid at the door for an order billed on delivery, so the
  /// credit check looks at what they will actually owe (payments already
  /// recorded are in the balance). [prepaid]: what was paid before dispatch,
  /// printed on the bill for the delivery person.
  void call(CustomerOrder order, OrderStatus newStatus,
      {required String userName, String? userId, BillNumber? bill, bool vatShop = false, double paidNow = 0, double prepaid = 0}) {
    final oldStatus = order.status;
    if (oldStatus == newStatus || oldStatus == OrderStatus.delivered || oldStatus == OrderStatus.cancelled) return;
    final bills = order.invoiceId == null && (newStatus == OrderStatus.outForDelivery || newStatus == OrderStatus.delivered);
    if (bills && vatShop && bill == null) throw StateError('Billing an order in a VAT shop issues a tax invoice: use Dispatch / Deliver.');
    if (newStatus == OrderStatus.cancelled && order.invoiceId != null) throw StateError('This order is billed: mark it not delivered first.');

    if (newStatus == OrderStatus.cancelled) {
      for (final item in order.items) {
        _products.releaseReservation(item.product, item.baseQty);
      }
    }
    if (bills) {
      for (final item in order.items) {
        _products.releaseReservation(item.product, item.baseQty);
        _products.decreaseStock(item.product, item.baseQty);
      }
      final sale = _invoice(order, userName: userName, userId: userId, bill: bill, paidNow: paidNow);
      if (newStatus == OrderStatus.outForDelivery) {
        order
          ..invoiceId = sale.id
          ..invoiceNumber = sale.invoiceNumber ?? sale.id
          ..prepaid = prepaid;
      }
    }

    _orders.setStatus(order, newStatus);

    _audit.record(userName, 'Order status changed', 'Order', entityId: order.id, oldValue: oldStatus.name, newValue: newStatus.name);
  }

  /// Goods the customer refused at the door ([refused]: order line index →
  /// quantity in that line's unit): recorded as negative lines against the
  /// order's bill, so stock comes back and the balance and books go down.
  /// [creditNote] numbers it in a VAT shop ([vat]: the shop's VAT terms).
  Sale doorReturn(CustomerOrder order, Map<int, double> refused, {required String userName, String? userId, VatTerms? vat, BillNumber? creditNote}) {
    if (order.invoiceId == null) throw StateError('Only a bill issued at dispatch can have refused goods.');
    if (vat != null && creditNote == null) throw StateError('Refused goods on a tax invoice need a credit note number.');
    final lines = <SaleItem>[];
    for (final MapEntry(key: index, value: qty) in refused.entries) {
      if (qty <= 0) continue;
      final i = order.items[index];
      if (qty > i.qty + 1e-9) throw StateError('More refused than was sent.');
      lines.add(SaleItem(product: i.product, qty: -qty, unitPrice: i.price, unit: i.unit, size: i.size, unitCost: i.product.purchasePrice > 0 ? i.product.purchasePrice * i.size : null));
    }
    final exempt = lines.where((i) => i.product.vatExempt).fold(0.0, (sum, i) => sum + i.lineTotal);
    final taxable = lines.fold(0.0, (sum, i) => sum + i.lineTotal) - exempt;
    final vatAmount = vat == null ? 0.0 : -vatOn(-taxable, vat);
    final sale = _sales.record(
      items: lines,
      isCredit: true,
      customer: order.customer,
      flaggedForApproval: false,
      createdByUserId: userId,
      createdByName: userName,
      orderId: order.id,
      vatAmount: vatAmount,
      vatIncluded: order.vatIncluded,
      exemptAmount: vat == null ? 0 : exempt,
      invoiceNumber: creditNote?.number,
      invoiceSeries: creditNote?.series,
      invoiceSeq: creditNote?.seq,
      buyerPan: order.customer.pan,
      returnOf: order.invoiceId,
    );
    for (final i in lines) {
      _products.increaseStock(i.product, -i.baseQty);
    }
    _customers.applyBalanceChange(order.customer, sale.total);
    _books.sale(sale);
    _audit.record(userName, 'Refused at delivery', 'Sale', entityId: sale.id,
        newValue: '${[for (final i in lines) '${i.product.name} ${-i.qty} ${i.unit}'].join(', ')} (${(-sale.total).toStringAsFixed(0)}) on bill ${order.invoiceNumber}');
    return sale;
  }

  /// Bills an order onto the customer's balance: a credit sale
  /// linked to the order.
  /// Delivering on credit past the customer's limit is allowed but flagged,
  /// audited and reported to the owner.
  Sale _invoice(CustomerOrder order, {required String userName, String? userId, BillNumber? bill, double paidNow = 0}) {
    final c = order.customer;
    final overBy = c.outstandingBalance + order.total - paidNow - c.creditLimit;
    final sale = _sales.record(
      // Delivery staff can't see costs (purchasePrice 0): no cost snapshot then.
      items: [
        for (final i in order.items)
          SaleItem(product: i.product, qty: i.qty, unitPrice: i.price, unit: i.unit, size: i.size, unitCost: i.product.purchasePrice > 0 ? i.product.purchasePrice * i.size : null),
      ],
      isCredit: true,
      customer: order.customer,
      flaggedForApproval: overBy > 0.005,
      createdByUserId: userId,
      createdByName: userName,
      orderId: order.id,
      vatAmount: order.vatAmount,
      vatIncluded: order.vatIncluded,
      exemptAmount: order.exemptAmount,
      invoiceNumber: bill?.number,
      invoiceSeries: bill?.series,
      invoiceSeq: bill?.seq,
      buyerPan: order.customer.pan,
    );
    _customers.applyBalanceChange(order.customer, sale.total);
    _books.sale(sale);
    if (overBy > 0.005) {
      _audit.record(userName, 'Delivered over credit limit', 'Order', entityId: order.id, newValue: 'over by ${overBy.toStringAsFixed(0)}');
      _notifications.notify('Over credit limit', '${c.name}: order ${order.id} billed by $userName takes them ${overBy.toStringAsFixed(0)} over their limit.', role: UserRole.owner);
    }
    _audit.record(userName, 'Order invoiced', 'Sale', entityId: sale.id, newValue: '${sale.total.toStringAsFixed(0)} for order ${order.id}');
    return sale;
  }
}
