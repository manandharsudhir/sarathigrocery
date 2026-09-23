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
  });

  final String id;
  String name;
  String phone;
  String location;
  double creditLimit;
  double outstandingBalance;
  DateTime? lastPaymentDate;
  double defaultDiscountPercent;

  CreditStatus get creditStatus {
    if (outstandingBalance > creditLimit) return CreditStatus.overdue;
    final daysSincePayment = lastPaymentDate == null
        ? 999
        : DateTime.now().difference(lastPaymentDate!).inDays;
    if (daysSincePayment > 30) return CreditStatus.dueSoon;
    return CreditStatus.safe;
  }
}
