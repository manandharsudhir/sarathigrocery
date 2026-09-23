// Drives a full business day through the real app code (several devices,
// each its own login) and records every commit with the account that made
// it. The result, firestore_tests/fixtures/app_writes.json, is replayed
// against firestore.rules by firestore_tests/replay.test.js — so the rules
// are checked against what the app actually writes, not hand-made samples.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sarathigrocery/app/injection.dart';
import 'package:sarathigrocery/core/data/remote_store.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/auth_repository.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/delivery_type.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_status.dart';
import 'package:sarathigrocery/features/purchasing/domain/entities/purchase_item.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_item.dart';

const _password = 'password123';

class _Recorder implements RemoteStore {
  _Recorder(this._inner, this._actor, this._log);

  final RemoteStore _inner;
  final String? Function() _actor;
  final List<Map<String, dynamic>> _log;

  @override
  Stream<List<Json>> watch(String collection, {String? id, Map<String, Object?> where = const {}}) => _inner.watch(collection, id: id, where: where);

  @override
  Future<Json?> get(String collection, String id) => _inner.get(collection, id);

  @override
  Future<List<String>> listIds(String collection) => _inner.listIds(collection);

  @override
  Future<void> commit(List<WriteOp> ops, {bool requireOnline = false}) async {
    await _inner.commit(ops, requireOnline: requireOnline);
    _log.add({
      'actor': _actor(),
      'ops': [
        for (final op in ops)
          switch (op) {
            PutOp(:final data) => {'kind': 'put', 'collection': op.collection, 'id': op.id, 'data': data},
            IncrementOp(:final deltas) => {'kind': 'increment', 'collection': op.collection, 'id': op.id, 'deltas': deltas},
            DeleteOp() => {'kind': 'delete', 'collection': op.collection, 'id': op.id},
          },
      ],
    });
  }
}

void main() {
  test('export the writes of a full business day for rules replay', () async {
    final store = InMemoryRemoteStore();
    final accounts = InMemoryAuthRepository();
    final log = <Map<String, dynamic>>[];

    Future<AppScope> device({String? phone}) async {
      final auth = accounts.forDevice();
      final scope = AppScope(store: _Recorder(store, () => auth.currentAccountId, log), authRepository: auth);
      if (phone != null) expect(await scope.auth.login(phone, _password), isTrue, reason: scope.auth.loginError);
      return scope;
    }

    // Setup + staff + customer logins.
    final owner = await device();
    expect(await owner.auth.setUpBusiness(businessName: 'Shop', ownerName: 'Owner', phone: '9800000001', password: _password, includeSampleData: true), isTrue);
    final o = owner.auth.currentUser!;
    for (final (phone, role) in [('9800000002', UserRole.accountant), ('9800000003', UserRole.employee), ('9800000005', UserRole.delivery)]) {
      expect(await owner.employees.createEmployeeAccount(name: role.name, phone: phone, password: _password, role: role, userName: o.name), isNull);
    }
    final gurung = owner.customers.customers.firstWhere((c) => c.name == 'Gurung General Store');
    expect(await owner.customers.createLogin(gurung, phone: '9800000004', password: _password, userName: o.name), isNull);
    final newShop = owner.customers.createCustomer(name: 'New Shop', phone: '9811', location: 'Patan', creditLimit: 20000, openingBalance: 5000, userName: o.name);
    owner.customers.updateCustomer(newShop, name: 'New Shop Pvt', phone: '9811', location: 'Patan', creditLimit: 25000, defaultDiscountPercent: 2, userName: o.name);
    owner.inventory.addCategory('Dairy');
    final ghee = owner.inventory.createProduct(name: 'Ghee', category: 'Dairy', unitPrice: 5000, purchasePrice: 4200, stockQty: 20, reorderLevel: 2);
    owner.inventory.updateProduct(ghee, userName: o.name, unitPrice: 5100);
    owner.settings.update(businessName: 'Shop', businessAddress: 'Koteshwor', businessPhone: '9800000001', defaultLowStockThreshold: 5, taxPercent: 0);
    await pumpEventQueue();

    final accountant = await device(phone: '9800000002');
    final employee = await device(phone: '9800000003');
    final delivery = await device(phone: '9800000005');
    final customer = await device(phone: '9800000004');

    // Customer orders; owner prepares and assigns; delivery collects with the code.
    customer.ordering.addToCart(customer.inventory.products.firstWhere((p) => p.name == 'Ghee'), 1);
    final placed = customer.ordering.placeOrder(customer.customers.customers.single, deliveryType: DeliveryType.delivery, address: 'Koteshwor', userName: 'Gurung', userId: customer.auth.currentUser!.id)!;
    await pumpEventQueue();
    final order = owner.ordering.orders.firstWhere((x) => x.id == placed.id);
    owner.ordering.assign(order, owner.ordering.deliverers.firstWhere((u) => u.role == UserRole.delivery), by: o);
    for (final st in [OrderStatus.confirmed, OrderStatus.preparing, OrderStatus.ready]) {
      owner.ordering.advanceOrderStatus(order, st, userName: o.name, userId: o.id);
    }
    await pumpEventQueue();
    final dOrder = delivery.ordering.orders.single;
    final d = delivery.auth.currentUser!;
    delivery.ordering.advanceOrderStatus(dOrder, OrderStatus.outForDelivery, userName: d.name, userId: d.id);
    await pumpEventQueue();
    final code = customer.ordering.deliveryCodeFor(customer.ordering.orders.single)!;
    await delivery.ordering.deliverAndCollect(dOrder, amount: 7000, method: PaymentMethod.cash, deliveryCode: code, collector: d);
    await pumpEventQueue();

    // Handover (short), customer confirms; counter payment disputed and reversed.
    final a = accountant.auth.currentUser!;
    accountant.payments.settle(accountant.payments.pendingHandover.single, 6500, receiver: a);
    await pumpEventQueue();
    final cu = customer.auth.currentUser!;
    final e = employee.auth.currentUser!;
    final eGurung = employee.customers.customers.firstWhere((c) => c.id == gurung.id);
    employee.payments.record(eGurung, 500, method: PaymentMethod.cash, collector: e);
    employee.payments.record(eGurung, 300, method: PaymentMethod.cash, collector: e);
    await pumpEventQueue();
    customer.payments.confirm(customer.payments.payments.firstWhere((p) => p.amount == 300), customerUser: cu);
    customer.payments.dispute(customer.payments.payments.firstWhere((p) => p.amount == 500), 'I paid 50', customerUser: cu);
    await pumpEventQueue();
    owner.payments.reverse(owner.payments.disputed.single, 'Entered wrong amount', owner: o);
    await pumpEventQueue();

    // Counter sales, cancel, purchases, money movements.
    final rice = employee.inventory.products.firstWhere((p) => p.name.startsWith('Basmati'));
    employee.sales.recordSale(items: [SaleItem(product: rice, qty: 1, unitPrice: rice.unitPrice)], discountPercent: 0, isCredit: false, userName: e.name, userId: e.id);
    employee.sales.recordSale(items: [SaleItem(product: rice, qty: 2, unitPrice: rice.unitPrice)], discountPercent: 0, isCredit: true, customer: eGurung, userName: e.name, userId: e.id);
    await pumpEventQueue();
    owner.sales.cancelSale(owner.sales.sales.last, 'customer changed mind', userName: o.name);
    final supplier = accountant.suppliers.suppliers.first;
    accountant.purchasing.createPurchase(supplier: supplier, items: [PurchaseItem(product: accountant.inventory.products.first, qty: 5, unitCost: 2700)], paidAmount: 5000, userName: a.name);
    accountant.suppliers.recordPayment(supplier, 1000, 'part', userName: a.name);
    accountant.cash.addExpense('Rent', 3000, 'Sept', createdByName: a.name);
    accountant.cash.addBankDeposit(2000, '');
    accountant.cash.addPartnerEntry('Partner A', 10000, 'loan', 'top-up');
    final aNewShop = accountant.customers.customers.firstWhere((c) => c.id == newShop.id);
    accountant.payments.record(aNewShop, 1200, method: PaymentMethod.wallet, reference: 'ESEWA-1', collector: a);
    await pumpEventQueue();

    // Owner delivers an unassigned order personally (takeover path), wallet payment + code.
    customer.ordering.addToCart(customer.inventory.products.firstWhere((p) => p.name == 'Ghee'), 1);
    final second = customer.ordering.placeOrder(customer.customers.customers.single, deliveryType: DeliveryType.pickup, userName: 'Gurung', userId: cu.id)!;
    await pumpEventQueue();
    final oSecond = owner.ordering.orders.firstWhere((x) => x.id == second.id);
    for (final st in [OrderStatus.confirmed, OrderStatus.preparing, OrderStatus.ready, OrderStatus.outForDelivery]) {
      owner.ordering.advanceOrderStatus(oSecond, st, userName: o.name, userId: o.id);
    }
    await pumpEventQueue();
    await owner.ordering.deliverAndCollect(oSecond, amount: 1000, method: PaymentMethod.wallet, reference: 'KHALTI-9',
        deliveryCode: customer.ordering.deliveryCodeFor(customer.ordering.orders.firstWhere((x) => x.id == second.id)), collector: o);
    await pumpEventQueue();

    // Staff admin, notifications.
    final staffEmployee = owner.employees.employees.firstWhere((u) => u.role == UserRole.employee);
    owner.employees.updatePermissions(staffEmployee, {Permission.viewSales, Permission.createSales, Permission.deliverOrders}, userName: o.name);
    owner.employees.setActive(owner.employees.employees.firstWhere((u) => u.role == UserRole.accountant), false, userName: o.name);
    owner.notificationRepository.markAllRead(o);
    customer.notificationRepository.markAllRead(cu);
    await pumpEventQueue();

    // Finally: owner resets the business.
    await owner.settings.resetBusiness(owner: o, typedName: 'Shop', password: _password);
    expect(store.documentCount, 0);

    final file = File('firestore_tests/fixtures/app_writes.json');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(log));
    expect(log.length, greaterThan(15));
  });
}
