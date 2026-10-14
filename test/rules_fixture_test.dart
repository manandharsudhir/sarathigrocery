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
import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/auth_repository.dart';
import 'package:sarathigrocery/core/utils/bs_date.dart';
import 'package:sarathigrocery/features/accounting/domain/entities/accounts.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product_pack.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/delivery_type.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_status.dart';
import 'package:sarathigrocery/features/purchasing/domain/entities/purchase_item.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_item.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_status.dart';
import 'package:sarathigrocery/features/settings/domain/entities/business_settings.dart';

import 'sign_up.dart';

const _password = 'password123';

class _Recorder implements RemoteStore {
  _Recorder(this._inner, this._actor, this._log);

  final RemoteStore _inner;
  /// The signed-in account, its email and whether it is verified (the
  /// replay's auth token).
  final (String?, String, bool) Function() _actor;
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
    final (actor, email, verified) = _actor();
    _log.add({
      'actor': actor,
      'actorEmail': email,
      'actorEmailVerified': verified,
      'ops': [
        for (final op in ops)
          switch (op) {
            PutOp(:final data) => {'kind': 'put', 'collection': op.collection, 'id': op.id, 'data': data},
            IncrementOp(:final deltas) => {'kind': 'increment', 'collection': op.collection, 'id': op.id, 'deltas': deltas},
            ArrayUnionOp(:final values) => {'kind': 'arrayUnion', 'collection': op.collection, 'id': op.id, 'values': values},
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

    Future<AppScope> device(String phone, {bool login = true}) async {
      final auth = accounts.forDevice();
      final scope = AppScope(store: _Recorder(store, () => (auth.currentAccountId, testEmail(phone), auth.emailVerified), log), authRepository: auth);
      if (login) expect(await scope.auth.login(testEmail(phone), _password), isTrue, reason: scope.auth.loginError);
      return scope;
    }

    // Setup + staff logins.
    final owner = await device('9800000001', login: false);
    expect(await signUp(owner, accounts, phone: '9800000001', password: _password, shop: 'Shop', sampleData: true), isTrue);
    final o = owner.auth.currentUser!;
    for (final (phone, role) in [('9800000002', UserRole.employee), ('9800000003', UserRole.employee), ('9800000005', UserRole.delivery)]) {
      expect((await owner.employees.createEmployeeAccount(name: role.name, email: testEmail(phone), phone: phone, password: _password, role: role, userName: o.name)).error, isNull);
    }
    AppUser staffWith(String phone) => owner.employees.employees.firstWhere((u) => u.phone == phone);
    // 9800000002 is staff who can handle cash & accounts.
    owner.employees.setCashAccess(staffWith('9800000002'), true, userName: o.name);
    // The day runs with every safeguard on; a segment near the end turns them off.
    owner.settings.enableAllSafeguards();
    final gurung = owner.customers.customers.firstWhere((c) => c.name == 'Gurung General Store');
    final newShop = owner.customers.createCustomer(name: 'New Shop', phone: '9811', location: 'Patan', creditLimit: 20000, openingBalance: 5000, by: o);
    owner.customers.updateCustomer(newShop, name: 'New Shop Pvt', phone: '9811', location: 'Patan', creditLimit: 25000, userName: o.name);
    owner.inventory.addCategory('Dairy');
    final ghee = owner.inventory.createProduct(
        name: 'Ghee', category: 'Dairy', unitPrice: 5000, purchasePrice: 4200, stockQty: 20, reorderLevel: 2, packs: const [ProductPack(label: 'box', size: 4, price: 19000)]);
    owner.inventory.updateProduct(ghee, userName: o.name, unitPrice: 5100, packs: const [ProductPack(label: 'box', size: 4, price: 19500)]);
    owner.settings.update(businessName: 'Shop', businessAddress: 'Koteshwor', businessPhone: '9800000001', defaultLowStockThreshold: 5, taxPercent: 0);
    await pumpEventQueue();

    final cashier = await device('9800000002');
    final employee = await device('9800000003');
    final delivery = await device('9800000005');
    final e = employee.auth.currentUser!;
    final eGurung = employee.customers.customers.firstWhere((c) => c.id == gurung.id);
    const signature = '10,10 500,400 900,120';

    // Employee takes an order; owner prepares and assigns; delivery collects with a signature.
    final placed = employee.ordering.placeOrderFor(eGurung, atMinimum({employee.inventory.products.firstWhere((p) => p.name == 'Ghee'): 1}),
        deliveryType: DeliveryType.delivery, address: 'Koteshwor', staff: e)!;
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
    await delivery.ordering.deliverAndCollect(dOrder, amount: 7000, method: PaymentMethod.cash, signature: signature, signedName: 'Gurung', collector: d);
    await pumpEventQueue();

    // Handover (short); unsigned counter payments confirmed/disputed by phone; dispute reversed.
    final a = cashier.auth.currentUser!;
    cashier.payments.settle(cashier.payments.pendingHandover.single, 6500, receiver: a);
    await pumpEventQueue();
    employee.payments.record(eGurung, 500, method: PaymentMethod.cash, collector: e);
    employee.payments.record(eGurung, 300, method: PaymentMethod.cash, collector: e);
    await pumpEventQueue();
    final toCall = cashier.payments.unconfirmed.where((p) => p.customer.id == gurung.id).toList();
    cashier.payments.confirmByPhone(toCall.firstWhere((p) => p.amount == 300), staff: a);
    cashier.payments.disputeOnBehalf(toCall.firstWhere((p) => p.amount == 500), 'paid 50', staff: a);
    await pumpEventQueue();
    owner.payments.reverse(owner.payments.disputed.single, 'Entered wrong amount', owner: o);
    await pumpEventQueue();

    // Counter sales, cancel, purchases, money movements.
    final rice = employee.inventory.products.firstWhere((p) => p.name.startsWith('Basmati'));
    employee.sales.recordSale(items: [SaleItem(product: rice, qty: 1, unitPrice: rice.unitPrice)], isCredit: false, userName: e.name, userId: e.id);
    employee.sales.recordSale(items: [SaleItem(product: rice, qty: 2, unitPrice: rice.unitPrice)], isCredit: true, customer: eGurung, userName: e.name, userId: e.id);
    // A box of ghee (pack), and the owner selling one below its minimum.
    final eGhee = employee.inventory.products.firstWhere((p) => p.name == 'Ghee');
    employee.sales.recordSale(items: [SaleItem(product: eGhee, qty: 1, unitPrice: 20000, unit: 'box', size: 4)], isCredit: false, userName: e.name, userId: e.id);
    owner.sales.recordSale(items: [SaleItem(product: ghee, qty: 1, unitPrice: 18000, unit: 'box', size: 4)], isCredit: false, userName: o.name, userId: o.id, allowBelowMinimum: true);
    await pumpEventQueue();
    owner.sales.cancelSale(owner.sales.sales.last, 'customer changed mind', userName: o.name);
    final supplier = cashier.suppliers.suppliers.first;
    cashier.purchasing.createPurchase(supplier: supplier, items: [PurchaseItem(product: cashier.inventory.products.first, qty: 5, unitCost: 2700)], paidAmount: 5000, userName: a.name);
    final cGhee = cashier.inventory.products.firstWhere((p) => p.name == 'Ghee');
    cashier.purchasing.createPurchase(supplier: supplier, items: [PurchaseItem(product: cGhee, qty: 2, unitCost: 16800, unit: 'box', size: 4)], userName: a.name);
    cashier.suppliers.recordPayment(supplier, 1000, 'part', userName: a.name);
    cashier.cash.addExpense('Rent', 3000, 'Sept', createdByName: a.name);
    cashier.cash.transfer('cash', 'bank', 2000, '', userName: a.name);
    cashier.cash.addExpense('Rent', 500, 'October', createdByName: a.name, account: 'bank');
    cashier.cash.otherPayment(3000, 'cash', 'shelves', userName: a.name);
    // Owner-only books: shares, capital, drawings, loans, dividend, an
    // adjustment, and closing last fiscal year.
    owner.accounting.saveSetup(owners: const [OwnerShare('Owner', 70), OwnerShare('Partner', 30)], moneyAccounts: const ['bank:NIC Asia'], by: o);
    owner.cash.capitalIn('Partner', 50000, 'bank:NIC Asia', userName: o.name);
    owner.cash.drawing('Owner', 1000, 'cash', 'personal', userName: o.name);
    owner.cash.drawingReturned('Owner', 400, 'cash', 'paid back', userName: o.name);
    owner.cash.loanReceived('Uncle', 20000, 'cash', userName: o.name);
    owner.cash.loanRepaid('Uncle', 5000, 'cash', userName: o.name);
    owner.cash.dividend(2000, 'bank:NIC Asia', userName: o.name);
    owner.accounting.manualEntry({Acc.receivables: 100, Acc.sales: -100}, 'accountant correction', DateTime.now(), by: o);
    // A co-owner: added by the founder, books capital, gets the founding
    // role and hands it back, then leaves.
    expect((await owner.employees.createEmployeeAccount(
            name: 'Partner', email: testEmail('9800000010'), phone: '9800000010', password: _password, role: UserRole.owner, userName: o.name, byFounder: true))
        .error, isNull);
    await pumpEventQueue();
    final partner = await device('9800000010');
    final pu = partner.auth.currentUser!;
    partner.cash.capitalIn('Partner', 10000, 'cash', userName: pu.name);
    owner.employees.handOverFounding(owner.employees.employees.firstWhere((u) => u.id == pu.id), by: o);
    await pumpEventQueue();
    partner.employees.handOverFounding(partner.employees.employees.firstWhere((u) => u.id == o.id), by: pu);
    await pumpEventQueue();
    await partner.auth.leaveShop();
    await pumpEventQueue();
    final lastYearEnd = BsDate.fiscalYearRange(BsDate.fromAd(DateTime.now()).fiscalYear - 1).$2;
    owner.accounting.closeYear(DateTime(lastYearEnd.year, lastYearEnd.month, lastYearEnd.day, 23, 59, 59), by: o);
    final aNewShop = cashier.customers.customers.firstWhere((c) => c.id == newShop.id);
    cashier.payments.record(aNewShop, 1200, method: PaymentMethod.wallet, reference: 'ESEWA-1', collector: a);
    await pumpEventQueue();

    // Owner takes and delivers an unassigned order personally (takeover path), wallet payment.
    final oGurung = owner.customers.customers.firstWhere((c) => c.id == gurung.id);
    final oSecond = owner.ordering.placeOrderFor(oGurung, atMinimum({owner.inventory.products.firstWhere((p) => p.name == 'Ghee'): 1}), deliveryType: DeliveryType.pickup, staff: o)!;
    await pumpEventQueue();
    for (final st in [OrderStatus.confirmed, OrderStatus.preparing, OrderStatus.ready, OrderStatus.outForDelivery]) {
      owner.ordering.advanceOrderStatus(oSecond, st, userName: o.name, userId: o.id);
    }
    await pumpEventQueue();
    await owner.ordering.deliverAndCollect(oSecond, amount: 1000, method: PaymentMethod.wallet, reference: 'KHALTI-9', signature: signature, signedName: 'Gurung', collector: o);
    await pumpEventQueue();

    // Sales staff add a customer and take a phone order; delivery with
    // signature; phone confirmation and dispute of counter payments.
    final walkIn = employee.customers.createCustomer(name: 'Walk-in Traders', phone: '9888', location: 'Kalanki', by: e);
    await pumpEventQueue();
    final phoneOrder = employee.ordering.placeOrderFor(
        employee.customers.customers.firstWhere((c) => c.id == walkIn.id), atMinimum({employee.inventory.products.firstWhere((p) => p.name == 'Ghee'): 1}),
        deliveryType: DeliveryType.delivery, address: 'Kalanki', staff: e)!;
    await pumpEventQueue();
    final oPhone = owner.ordering.orders.firstWhere((x) => x.id == phoneOrder.id);
    owner.ordering.assign(oPhone, owner.ordering.deliverers.firstWhere((u) => u.role == UserRole.delivery), by: o);
    for (final st in [OrderStatus.confirmed, OrderStatus.preparing, OrderStatus.ready]) {
      owner.ordering.advanceOrderStatus(oPhone, st, userName: o.name, userId: o.id);
    }
    await pumpEventQueue();
    final dPhone = delivery.ordering.orders.firstWhere((x) => x.id == phoneOrder.id);
    delivery.ordering.advanceOrderStatus(dPhone, OrderStatus.outForDelivery, userName: d.name, userId: d.id);
    await pumpEventQueue();
    await delivery.ordering.deliverAndCollect(dPhone, amount: 2000, method: PaymentMethod.cash, signature: signature, signedName: 'Shyam', collector: d);
    final eWalkIn = employee.customers.customers.firstWhere((c) => c.id == walkIn.id);
    employee.payments.record(eWalkIn, 400, method: PaymentMethod.cash, collector: e);
    employee.payments.record(eWalkIn, 600, method: PaymentMethod.cash, collector: e);
    await pumpEventQueue();
    final walkInCalls = cashier.payments.unconfirmed.where((p) => p.customer.id == walkIn.id).toList();
    cashier.payments.confirmByPhone(walkInCalls.firstWhere((p) => p.amount == 400), staff: a);
    cashier.payments.disputeOnBehalf(walkInCalls.firstWhere((p) => p.amount == 600), 'paid 60', staff: a);
    await pumpEventQueue();

    // Safeguards off: unsigned delivery settled by the delivery person at
    // once; unsigned counter payment, no phone check, counted in by its collector.
    final quick = employee.ordering.placeOrderFor(eGurung, atMinimum({employee.inventory.products.firstWhere((p) => p.name == 'Ghee'): 1}),
        deliveryType: DeliveryType.delivery, address: 'Koteshwor', staff: e)!;
    await pumpEventQueue();
    final oQuick = owner.ordering.orders.firstWhere((x) => x.id == quick.id);
    owner.ordering.assign(oQuick, owner.ordering.deliverers.firstWhere((u) => u.role == UserRole.delivery), by: o);
    for (final st in [OrderStatus.confirmed, OrderStatus.preparing, OrderStatus.ready]) {
      owner.ordering.advanceOrderStatus(oQuick, st, userName: o.name, userId: o.id);
    }
    for (final g in Safeguard.values) {
      owner.settings.setSafeguard(g, false);
    }
    await pumpEventQueue();
    final dQuick = delivery.ordering.orders.firstWhere((x) => x.id == quick.id);
    delivery.ordering.advanceOrderStatus(dQuick, OrderStatus.outForDelivery, userName: d.name, userId: d.id);
    await pumpEventQueue();
    final quickPaid = await delivery.ordering.deliverAndCollect(dQuick, amount: 5100, method: PaymentMethod.cash, collector: d);
    expect(quickPaid!.isSettled && quickPaid.autoConfirmed, isTrue);
    expect(employee.payments.record(eGurung, 250, method: PaymentMethod.cash, collector: e).isSettled, isTrue);
    await pumpEventQueue();

    // VAT registered: numbered tax invoices at the counter and on delivery,
    // a credit note, a purchase with the supplier's VAT bill, VAT paid.
    owner.settings.setVat(registered: true, pan: '601234567', rate: 13, pricesIncludeVat: true);
    final vatOrder = employee.ordering.placeOrderFor(eGurung, atMinimum({employee.inventory.products.firstWhere((p) => p.name == 'Ghee'): 1}),
        deliveryType: DeliveryType.delivery, address: 'Koteshwor', staff: e)!;
    await pumpEventQueue();
    final vatRice = employee.inventory.products.firstWhere((p) => p.name.startsWith('Basmati'));
    final taxSale = await employee.sales.sell(items: [SaleItem(product: vatRice, qty: 1, unitPrice: vatRice.unitPrice)], isCredit: false, userName: e.name, userId: e.id);
    expect(taxSale.invoiceNumber, isNotNull);
    await employee.sales.sell(items: [SaleItem(product: vatRice, qty: 1, unitPrice: vatRice.unitPrice)], isCredit: true, customer: eGurung, userName: e.name, userId: e.id);
    final oVat = owner.ordering.orders.firstWhere((x) => x.id == vatOrder.id);
    owner.ordering.assign(oVat, owner.ordering.deliverers.firstWhere((u) => u.role == UserRole.delivery), by: o);
    await pumpEventQueue();
    final dVat = delivery.ordering.orders.firstWhere((x) => x.id == vatOrder.id);
    await delivery.ordering.deliverAndCollect(dVat, amount: 0, method: PaymentMethod.cash, collector: d);
    await pumpEventQueue();
    await owner.sales.reverse(owner.sales.sales.firstWhere((x) => x.id == taxSale.id), SaleStatus.returned, 'damaged', userName: o.name);
    owner.purchasing.createPurchase(
      supplier: owner.suppliers.suppliers.first,
      items: [PurchaseItem(product: owner.inventory.products.first, qty: 2, unitCost: 2700)],
      paidAmount: 6102,
      userName: o.name,
      vatAmount: 702,
      supplierBillNo: 'RT-55',
      supplierBillDate: DateTime.now(),
    );
    owner.cash.vatPaid(1000, 702, 'cash', 'test month', userName: o.name);
    await pumpEventQueue();

    // Staff admin, notifications.
    final staffEmployee = staffWith('9800000003');
    owner.employees.updatePermissions(staffEmployee, {Permission.viewSales, Permission.createSales, Permission.deliverOrders}, userName: o.name);
    owner.employees.setActive(staffWith('9800000002'), false, userName: o.name);
    owner.notificationRepository.markAllRead(o);
    delivery.notificationRepository.markAllRead(d);
    await pumpEventQueue();

    // Finally: owner resets the business.
    await owner.settings.resetBusiness(owner: o, typedName: 'Shop', password: _password);
    expect(store.documentCount('shops'), 0, reason: 'the shop doc and its whole subtree are gone');

    // A second shop adds an existing login (staff of the first shop) as staff.
    final owner2 = await device('9800000009', login: false);
    expect(await signUp(owner2, accounts, phone: '9800000009', password: _password, shop: 'Shop 2', owner: 'Owner 2'), isTrue);
    final joined = await owner2.employees.createEmployeeAccount(name: 'Shared', email: testEmail('9800000003'), phone: '9800000003', password: '', role: UserRole.employee, userName: 'Owner 2');
    expect(joined, (error: null, existingLogin: true));
    await pumpEventQueue();

    // Account deletion: the shared staff login (anonymised in Shop 2), then
    // Shop 2's owner (shop wiped).
    final shared = await device('9800000003');
    await shared.auth.deleteAccount(password: _password);
    await owner2.auth.deleteAccount(password: _password, typedShopName: 'Shop 2');
    expect(store.documentCount('shops'), 0);

    final file = File('firestore_tests/fixtures/app_writes.json');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(log));
    expect(log.length, greaterThan(15));
  });
}
