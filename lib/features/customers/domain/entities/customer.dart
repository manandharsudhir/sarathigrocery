import 'package:sarathigrocery/features/customers/domain/entities/credit_status.dart';

class Customer {
  Customer({
    required this.id,
    required this.name,
    required this.phone,
    required this.location,
    required this.creditLimit,
    this.outstandingBalance = 0,
    this.lastPaymentDate,
    this.defaultDiscountPercent = 0,
    this.openingBalance,
    this.hasAppLogin = false,
  });

  final String id;
  String name;
  String phone;
  String location;
  double creditLimit;
  double outstandingBalance;
  DateTime? lastPaymentDate;
  double defaultDiscountPercent;

  /// Udharo carried in when the customer was added (before any bill or
  /// payment in this app). Null for records created before this existed.
  /// Lets the statement prove `outstandingBalance` = opening + bills −
  /// payments, so an unexplained change to a balance is visible.
  final double? openingBalance;

  /// Whether this customer has their own app login. Without one they can't
  /// see delivery codes or confirm payments in the app, so deliveries need
  /// their signature and payments are confirmed by a phone call instead.
  bool hasAppLogin;

  CreditStatus get creditStatus {
    if (outstandingBalance > creditLimit) return CreditStatus.overdue;
    final daysSincePayment = lastPaymentDate == null
        ? 999
        : DateTime.now().difference(lastPaymentDate!).inDays;
    if (daysSincePayment > 30) return CreditStatus.dueSoon;
    return CreditStatus.safe;
  }
}
