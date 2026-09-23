import 'package:flutter/foundation.dart';

import 'package:sarathigrocery/core/services/app_signal.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/auth_repository.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/user_repository.dart';
import 'package:sarathigrocery/features/cash/domain/repositories/cash_repository.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/customers/domain/repositories/customer_repository.dart';
import 'package:sarathigrocery/features/customers/domain/usecases/create_customer_login.dart';
import 'package:sarathigrocery/features/customers/domain/usecases/record_payment.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';

class CustomersController extends ChangeNotifier {
  CustomersController(this._repository, this._audit, CashRepository cash, NotificationRepository notifications, this._users, AuthRepository auth)
      : _recordPayment = RecordPayment(_repository, cash, _audit, notifications),
        _createLogin = CreateCustomerLogin(_users, auth, _audit);

  final CustomerRepository _repository;
  final AuditRepository _audit;
  final UserRepository _users;
  final RecordPayment _recordPayment;
  final CreateCustomerLogin _createLogin;

  CustomerRepository get repository => _repository;

  List<Customer> get customers => _repository.customers;

  double get totalOutstanding => _repository.totalOutstanding;

  AppUser? loginFor(Customer customer) => _users.userForCustomer(customer.id);

  void recordPayment(Customer customer, double amount, String note, {required String userName}) {
    _recordPayment(customer, amount, note, userName: userName);
    notifyListeners();
    AppSignal.instance.ping();
  }

  Customer createCustomer({required String name, required String phone, required String location, required double creditLimit, double defaultDiscountPercent = 0, required String userName}) {
    final customer = _repository.create(name: name, phone: phone, location: location, creditLimit: creditLimit, defaultDiscountPercent: defaultDiscountPercent);
    _audit.record(userName, 'Customer added', 'Customer', entityId: customer.id, newValue: name);
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
