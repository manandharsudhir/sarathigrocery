import 'package:sarathigrocery/features/accounting/domain/books.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';
import 'package:sarathigrocery/features/customers/domain/repositories/customer_repository.dart';
import 'package:sarathigrocery/features/inventory/domain/repositories/product_repository.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/customer_order.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_status.dart';
import 'package:sarathigrocery/features/ordering/domain/repositories/order_repository.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_item.dart';
import 'package:sarathigrocery/features/sales/domain/entities/vat.dart';
import 'package:sarathigrocery/features/sales/domain/repositories/sale_repository.dart';

/// Advances (or cancels) an order. Cancelling releases reserved stock.
/// Delivering finalizes the reservation into a stock deduction AND bills
/// the customer: an invoice (credit sale linked to the order) is recorded
/// and the order total goes onto their balance. Whatever they pay at the
/// door is then recorded as a payment against that balance.
class AdvanceOrderStatus {
  AdvanceOrderStatus(this._orders, this._products, this._sales, this._customers, this._audit, this._books, this._notifications);

  final OrderRepository _orders;
  final ProductRepository _products;
  final SaleRepository _sales;
  final CustomerRepository _customers;
  final AuditRepository _audit;
  final Books _books;
  final NotificationRepository _notifications;

  /// Delivering in a VAT shop issues a tax invoice: [bill] is its number.
  /// [paidNow]: what the customer pays at the door (Deliver & collect), so the
  /// credit check looks at what they will actually owe.
  void call(CustomerOrder order, OrderStatus newStatus, {required String userName, String? userId, BillNumber? bill, bool vatShop = false, double paidNow = 0}) {
    final oldStatus = order.status;
    if (oldStatus == newStatus || oldStatus == OrderStatus.delivered || oldStatus == OrderStatus.cancelled) return;
    if (newStatus == OrderStatus.delivered && vatShop && bill == null) throw StateError('Delivering in a VAT shop issues a tax invoice: use Deliver.');

    if (newStatus == OrderStatus.cancelled) {
      for (final item in order.items) {
        _products.releaseReservation(item.product, item.baseQty);
      }
    }
    if (newStatus == OrderStatus.delivered) {
      for (final item in order.items) {
        _products.releaseReservation(item.product, item.baseQty);
        _products.decreaseStock(item.product, item.baseQty);
      }
      _invoice(order, userName: userName, userId: userId, bill: bill, paidNow: paidNow);
    }

    _orders.setStatus(order, newStatus);

    _audit.record(userName, 'Order status changed', 'Order', entityId: order.id, oldValue: oldStatus.name, newValue: newStatus.name);
  }

  /// Bills a delivered order onto the customer's balance: a credit sale
  /// linked to the order.
  /// Delivering on credit past the customer's limit is allowed but flagged,
  /// audited and reported to the owner.
  void _invoice(CustomerOrder order, {required String userName, String? userId, BillNumber? bill, double paidNow = 0}) {
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
      _notifications.notify('Over credit limit', '${c.name}: order ${order.id} delivered by $userName takes them ${overBy.toStringAsFixed(0)} over their limit.', role: UserRole.owner);
    }
    _audit.record(userName, 'Order invoiced', 'Sale', entityId: sale.id, newValue: '${sale.total.toStringAsFixed(0)} for order ${order.id}');
  }
}
