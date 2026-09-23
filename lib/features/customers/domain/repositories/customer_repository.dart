import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';

abstract class CustomerRepository {
  List<Customer> get customers;

  double get totalOutstanding;

  Customer create({required String name, required String phone, required String location, required double creditLimit, double defaultDiscountPercent = 0});

  /// Persists edited profile fields (not the balance — see [applyBalanceChange]).
  void update(Customer customer);

  /// Raw balance mutation, no ledger/audit/notification side effects —
  /// those are owned by the use case that calls this (a credit sale, a
  /// payment, a return, ...).
  void applyBalanceChange(Customer customer, double delta, {DateTime? paymentDate});
}
