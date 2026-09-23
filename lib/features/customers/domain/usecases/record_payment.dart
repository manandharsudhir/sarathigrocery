import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/cash/domain/entities/cash_entry_type.dart';
import 'package:sarathigrocery/features/cash/domain/repositories/cash_repository.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/customers/domain/repositories/customer_repository.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';

/// Records a customer payment: reduces their outstanding balance, logs it in
/// the cash ledger, audits it, and notifies the owner.
class RecordPayment {
  RecordPayment(this._customers, this._cash, this._audit, this._notifications);

  final CustomerRepository _customers;
  final CashRepository _cash;
  final AuditRepository _audit;
  final NotificationRepository _notifications;

  void call(Customer customer, double amount, String note, {required String userName}) {
    _customers.applyBalanceChange(customer, -amount, paymentDate: DateTime.now());
    _cash.addLedgerEntry(
      type: CashEntryType.collection,
      amount: amount,
      note: note.isEmpty ? 'Collection from ${customer.name}' : note,
      reference: customer.id,
    );
    _audit.record(userName, 'Payment recorded', 'Customer', entityId: customer.id, newValue: amount.toStringAsFixed(0));
    _notifications.notify('Payment received', 'NPR ${amount.toStringAsFixed(0)} from ${customer.name}', role: UserRole.owner);
  }
}
