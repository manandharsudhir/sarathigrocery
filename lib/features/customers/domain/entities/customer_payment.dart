import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';

enum PaymentMethod { cash, wallet, bank, cheque }

String ledgerAccountFor(PaymentMethod m) => switch (m) {
      PaymentMethod.cash => 'cash',
      PaymentMethod.wallet => 'wallet',
      PaymentMethod.bank || PaymentMethod.cheque => 'bank',
    };

/// A payment step that isn't allowed, with a user-presentable [message].
class PaymentException implements Exception {
  PaymentException(this.message);

  final String message;

  @override
  String toString() => message;
}

String paymentMethodLabel(PaymentMethod m) => switch (m) {
      PaymentMethod.cash => 'Cash',
      PaymentMethod.wallet => 'Wallet / QR',
      PaymentMethod.bank => 'Bank transfer',
      PaymentMethod.cheque => 'Cheque',
    };

/// Money a customer handed over. Never edited or deleted — every later step
/// (customer confirmation, handover to the till, reversal) only fills in
/// its own fields, and the backend refuses anything else.
///
/// Two independent checks make it trustworthy:
/// - **Customer side** — signed for at the door, or confirmed by a phone
///   call from staff other than the collector; or disputed.
/// - **Business side** — "settled": someone with `reconcileCash` (not the
///   collector) counted the cash into the till or verified the reference.
class CustomerPayment {
  CustomerPayment({
    required this.id,
    required this.date,
    required this.customer,
    required this.amount,
    required this.method,
    this.reference = '',
    this.orderId,
    this.appliedToOrder = 0,
    required this.balanceAfter,
    required this.collectedById,
    required this.collectedByName,
    this.signature,
    this.signedName = '',
    this.autoConfirmed = false,
    this.phoneConfirmedAt,
    this.phoneConfirmedByName = '',
    this.disputedAt,
    this.disputeNote = '',
    this.settledAt,
    this.settledAmount,
    this.settledById,
    this.settledByName = '',
    this.reversedAt,
    this.reversedByName = '',
    this.reversalReason = '',
  });

  final String id;
  final DateTime date;
  final Customer customer;
  final double amount;
  final PaymentMethod method;

  /// Wallet transaction id / bank reference / cheque number.
  final String reference;

  /// The order this was collected against; it's paid off first.
  final String? orderId;

  /// Receipt figures as shown at collection time.
  final double appliedToOrder;
  final double balanceAfter;

  final String collectedById;
  final String collectedByName;

  /// Customer's handwritten signature (encoded `Signature`) and the name
  /// they gave, captured on the collector's phone.
  final String? signature;
  final String signedName;

  /// Recorded unsigned while the shop's phone-check safeguard was off, so it
  /// needs no customer confirmation.
  final bool autoConfirmed;

  /// Staff other than the collector phoned the customer, who confirmed.
  DateTime? phoneConfirmedAt;
  String phoneConfirmedByName;

  /// Who recorded the dispute (staff, on the customer's behalf after a call).
  String disputedByName = '';

  DateTime? disputedAt;
  String disputeNote;

  DateTime? settledAt;
  double? settledAmount;
  String? settledById;
  String settledByName;

  DateTime? reversedAt;
  String reversedByName;
  String reversalReason;

  bool get isReversed => reversedAt != null;
  bool get isSettled => settledAt != null;
  bool get isDisputed => disputedAt != null;
  bool get confirmedBySignature => signature != null;
  bool get isCustomerConfirmed => confirmedBySignature || autoConfirmed || phoneConfirmedAt != null;

  /// Counted less than collected — owed by the collector.
  double get shortfall => isSettled ? amount - settledAmount! : 0;

  /// Collected but not yet in the till / verified.
  bool get isPendingHandover => !isSettled && !isReversed;

  double get appliedToPreviousBalance => amount - appliedToOrder;
}
