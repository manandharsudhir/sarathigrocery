import 'package:flutter/foundation.dart';

import 'package:sarathigrocery/core/services/app_signal.dart';
import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_statement.dart';
import 'package:sarathigrocery/features/customers/domain/repositories/payment_repository.dart';
import 'package:sarathigrocery/features/customers/domain/usecases/record_payment.dart';
import 'package:sarathigrocery/features/customers/domain/usecases/respond_to_payment.dart';
import 'package:sarathigrocery/features/customers/domain/usecases/reverse_payment.dart';
import 'package:sarathigrocery/features/customers/domain/usecases/settle_payment.dart';
import 'package:sarathigrocery/features/sales/domain/repositories/sale_repository.dart';

/// Customer payments: recording, the customer's confirmation/dispute, cash
/// handover to the till, owner reversal, and statements. Actions throw
/// [PaymentException] with a displayable message.
class PaymentsController extends ChangeNotifier {
  PaymentsController(this._payments, this._sales, this._record, this._settle, this._respond, this._reverse);

  final PaymentRepository _payments;
  final SaleRepository _sales;
  final RecordPayment _record;
  final SettlePayment _settle;
  final RespondToPayment _respond;
  final ReversePayment _reverse;

  List<CustomerPayment> get payments => _payments.payments;

  List<CustomerPayment> forCustomer(Customer customer) => payments.where((p) => p.customer.id == customer.id).toList();

  List<CustomerPayment> forOrder(String orderId) => payments.where((p) => p.orderId == orderId).toList();

  CustomerStatement statementFor(Customer customer) => buildStatement(customer, _sales.sales, payments);

  /// Collected but not yet received into the till / verified, oldest first.
  List<CustomerPayment> get pendingHandover => payments.where((p) => p.isPendingHandover).toList();

  List<CustomerPayment> pendingHandoverBy(String collectorId) => pendingHandover.where((p) => p.collectedById == collectorId).toList();

  List<CustomerPayment> get disputed => payments.where((p) => p.isDisputed && !p.isReversed).toList();

  /// Not confirmed by code or by the customer, not disputed — worth a look.
  List<CustomerPayment> get unconfirmed => payments.where((p) => !p.isCustomerConfirmed && !p.isDisputed && !p.isReversed).toList();

  List<CustomerPayment> get shortfalls => payments.where((p) => p.shortfall > 0).toList();

  void _changed() {
    notifyListeners();
    AppSignal.instance.ping();
  }

  CustomerPayment record(Customer customer, double amount, {required PaymentMethod method, String reference = '', required AppUser collector}) {
    final payment = _record(customer, amount, method: method, reference: reference, collector: collector);
    _changed();
    return payment;
  }

  void settle(CustomerPayment payment, double counted, {required AppUser receiver}) {
    _settle(payment, counted, receiver: receiver);
    _changed();
  }

  void confirm(CustomerPayment payment, {required AppUser customerUser}) {
    _respond.confirm(payment, customerUser: customerUser);
    _changed();
  }

  void dispute(CustomerPayment payment, String note, {required AppUser customerUser}) {
    _respond.dispute(payment, note, customerUser: customerUser);
    _changed();
  }

  void reverse(CustomerPayment payment, String reason, {required AppUser owner}) {
    _reverse(payment, reason, owner: owner);
    _changed();
  }
}
