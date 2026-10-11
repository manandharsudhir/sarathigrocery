import 'package:flutter/foundation.dart';

import 'package:sarathigrocery/core/services/app_signal.dart';
import 'package:sarathigrocery/features/accounting/domain/books.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/customers/domain/repositories/customer_repository.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/payments_controller.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';

class CustomersController extends ChangeNotifier {
  CustomersController(this._repository, this._audit, this.payments, this._notifications, this._books);

  final Books _books;

  final NotificationRepository _notifications;

  /// Payments/statements for these customers (exposed here so customer
  /// screens don't need a second controller threaded through every caller).
  final PaymentsController payments;

  final CustomerRepository _repository;
  final AuditRepository _audit;

  CustomerRepository get repository => _repository;

  List<Customer> get customers => _repository.customers;

  double get totalOutstanding => _repository.totalOutstanding;

  /// Anyone with manageCustomers sets terms freely. Sales staff with only
  /// createCustomers can add a customer, but with no credit (limit 0, no
  /// opening udharo) until the owner or cash staff sets terms —
  /// otherwise anyone at the counter could grant credit.
  Customer createCustomer({
    required String name,
    required String phone,
    required String location,
    double creditLimit = 0,
    double openingBalance = 0,
    String pan = '',
    required AppUser by,
  }) {
    final canSetTerms = by.can(Permission.manageCustomers);
    if (!canSetTerms && !by.can(Permission.createCustomers)) throw StateError('Not allowed to add customers');
    final customer = _repository.create(
      name: name,
      phone: phone,
      location: location,
      creditLimit: canSetTerms ? creditLimit : 0,
      openingBalance: canSetTerms ? openingBalance : 0,
      pan: pan.trim(),
    );
    // Udharo from before the app is part of the opening capital.
    if ((customer.openingBalance ?? 0) > 0) _books.customerOpening(customer, by: by.name);
    _audit.record(by.name, 'Customer added', 'Customer', entityId: customer.id, newValue: openingBalance == 0 || !canSetTerms ? name : '$name (old udharo ${openingBalance.toStringAsFixed(0)})');
    if (!canSetTerms) {
      _notifications.notify('New customer: $name', 'Added by ${by.name} with no credit. Set their credit limit if they buy on udharo.', role: UserRole.owner);
    }
    notifyListeners();
    AppSignal.instance.ping();
    return customer;
  }

  void updateCustomer(Customer customer, {required String name, required String phone, required String location, required double creditLimit, required String userName, String? pan}) {
    if (creditLimit != customer.creditLimit) {
      _audit.record(userName, 'Credit limit changed', 'Customer', entityId: customer.id, oldValue: customer.creditLimit.toStringAsFixed(0), newValue: creditLimit.toStringAsFixed(0));
    }
    customer
      ..name = name
      ..phone = phone
      ..location = location
      ..creditLimit = creditLimit
      ..pan = pan?.trim() ?? customer.pan;
    _repository.update(customer);
    notifyListeners();
    AppSignal.instance.ping();
  }
}
