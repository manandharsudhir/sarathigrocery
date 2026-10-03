import 'package:flutter/foundation.dart';

import 'package:sarathigrocery/core/services/app_signal.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/auth_repository.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/user_repository.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/customers/domain/repositories/customer_repository.dart';
import 'package:sarathigrocery/features/customers/domain/usecases/create_customer_login.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/payments_controller.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';

class CustomersController extends ChangeNotifier {
  CustomersController(this._repository, this._audit, this._users, AuthRepository auth, this.payments, this._notifications) : _createLogin = CreateCustomerLogin(_users, _repository, auth, _audit);

  final NotificationRepository _notifications;

  /// Payments/statements for these customers (exposed here so customer
  /// screens don't need a second controller threaded through every caller).
  final PaymentsController payments;

  final CustomerRepository _repository;
  final AuditRepository _audit;
  final UserRepository _users;
  final CreateCustomerLogin _createLogin;

  CustomerRepository get repository => _repository;

  List<Customer> get customers => _repository.customers;

  double get totalOutstanding => _repository.totalOutstanding;

  AppUser? loginFor(Customer customer) => _users.userForCustomer(customer.id);

  /// Anyone with manageCustomers sets terms freely. Sales staff with only
  /// createCustomers can add a customer, but with no credit (limit 0, no
  /// opening udharo or discount) until the owner/accountant sets terms —
  /// otherwise anyone at the counter could grant credit.
  Customer createCustomer({
    required String name,
    required String phone,
    required String location,
    double creditLimit = 0,
    double defaultDiscountPercent = 0,
    double openingBalance = 0,
    required AppUser by,
  }) {
    final canSetTerms = by.can(Permission.manageCustomers);
    if (!canSetTerms && !by.can(Permission.createCustomers)) throw StateError('Not allowed to add customers');
    final customer = _repository.create(
      name: name,
      phone: phone,
      location: location,
      creditLimit: canSetTerms ? creditLimit : 0,
      defaultDiscountPercent: canSetTerms ? defaultDiscountPercent : 0,
      openingBalance: canSetTerms ? openingBalance : 0,
    );
    _audit.record(by.name, 'Customer added', 'Customer', entityId: customer.id, newValue: openingBalance == 0 || !canSetTerms ? name : '$name (opening balance ${openingBalance.toStringAsFixed(0)})');
    if (!canSetTerms) {
      _notifications.notify('New customer: $name', 'Added by ${by.name} with no credit. Set their credit limit if they buy on udharo.', role: UserRole.owner);
    }
    notifyListeners();
    AppSignal.instance.ping();
    return customer;
  }

  void updateCustomer(Customer customer, {required String name, required String phone, required String location, required double creditLimit, required double defaultDiscountPercent, required String userName}) {
    if (creditLimit != customer.creditLimit) {
      _audit.record(userName, 'Credit limit changed', 'Customer', entityId: customer.id, oldValue: customer.creditLimit.toStringAsFixed(0), newValue: creditLimit.toStringAsFixed(0));
    }
    if (defaultDiscountPercent != customer.defaultDiscountPercent) {
      _audit.record(userName, 'Customer discount changed', 'Customer', entityId: customer.id, oldValue: '${customer.defaultDiscountPercent}%', newValue: '$defaultDiscountPercent%');
    }
    customer
      ..name = name
      ..phone = phone
      ..location = location
      ..creditLimit = creditLimit
      ..defaultDiscountPercent = defaultDiscountPercent;
    _repository.update(customer);
    notifyListeners();
    AppSignal.instance.ping();
  }

  /// Returns an error message, or null on success.
  Future<String?> createLogin(Customer customer, {required String phone, required String password, required String userName}) async {
    try {
      final error = await _createLogin(customer, phone: phone, password: password, userName: userName);
      if (error != null) return error;
    } on AuthException catch (e) {
      return e.message;
    }
    notifyListeners();
    AppSignal.instance.ping();
    return null;
  }
}
