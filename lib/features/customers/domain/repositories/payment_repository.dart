import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';

abstract class PaymentRepository {
  /// Oldest first.
  List<CustomerPayment> get payments;

  void add(CustomerPayment payment);

  /// Persists a later step (confirmation, dispute, settlement, reversal).
  void update(CustomerPayment payment);
}
