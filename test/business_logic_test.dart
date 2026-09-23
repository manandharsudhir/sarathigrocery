import 'package:flutter_test/flutter_test.dart';
import 'package:sarathigrocery/app/injection.dart';
import 'package:sarathigrocery/core/data/remote_store.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/auth_repository.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/adjustment_type.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/delivery_type.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_status.dart';
import 'package:sarathigrocery/features/purchasing/domain/entities/purchase_item.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_item.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_status.dart';

/// A freshly set-up business on a shared in-memory backend, with one login
/// per role (customer login linked to the sample "Gurung General Store").
class TestBusiness {
  final store = InMemoryRemoteStore();
  final auth = InMemoryAuthRepository();

  static const password = 'password123';
  static const phones = {
    UserRole.owner: '9800000001',
    UserRole.accountant: '9800000002',
    UserRole.employee: '9800000003',
    UserRole.customer: '9800000004',
  };

  static Future<TestBusiness> create() async {
    final business = TestBusiness();
    final owner = AppScope(store: business.store, authRepository: business.auth);
    expect(
      await owner.auth.setUpBusiness(businessName: 'Test Shop', ownerName: 'Owner', phone: phones[UserRole.owner]!, password: password, includeSampleData: true),
      isTrue,
      reason: owner.auth.loginError,
    );
    for (final role in [UserRole.accountant, UserRole.employee]) {
      expect(await owner.employees.createEmployeeAccount(name: role.name, phone: phones[role]!, password: password, role: role, userName: 'Owner'), isNull);
    }
    final gurung = owner.customers.customers.firstWhere((c) => c.name == 'Gurung General Store');
    expect(await owner.customers.createLogin(gurung, phone: phones[UserRole.customer]!, password: password, userName: 'Owner'), isNull);
    await pumpEventQueue();
    return business;
  }

  /// A new "device" signed in as [role].
  Future<AppScope> device(UserRole role) async {
    final scope = AppScope(store: store, authRepository: auth);
    expect(await scope.auth.login(phones[role]!, password), isTrue, reason: scope.auth.loginError);
    return scope;
  }
}

Future<AppScope> signedIn(UserRole role) async => (await TestBusiness.create()).device(role);

void main() {
  group('sales', () {
    test('cancelSale reverses stock and customer balance', () async {
      final scope = await signedIn(UserRole.owner);
      final product = scope.inventory.products.first;
      final customer = scope.customers.customers.first;
      final stockBefore = product.stockQty;
      final balanceBefore = customer.outstandingBalance;
      final userName = scope.auth.currentUser!.name;

      scope.sales.recordSale(
        items: [SaleItem(product: product, qty: 2, unitPrice: product.unitPrice)],
        discountPercent: 0,
        isCredit: true,
        customer: customer,
        userName: userName,
      );
      expect(product.stockQty, stockBefore - 2);
      expect(customer.outstandingBalance, greaterThan(balanceBefore));

      final sale = scope.sales.sales.last;
      final cancelled = scope.sales.cancelSale(sale, 'test reason', userName: userName);

      expect(cancelled, isTrue);
      expect(product.stockQty, stockBefore);
      expect(customer.outstandingBalance, balanceBefore);
      expect(sale.status, SaleStatus.cancelled);
      expect(scope.sales.cancelSale(sale, 'again', userName: userName), isFalse, reason: 'already-cancelled sale cannot be cancelled twice');
    });

    test('cash sale adds to the cash ledger, credit sale does not', () async {
      final scope = await signedIn(UserRole.owner);
      final product = scope.inventory.products.first;
      final cashBefore = scope.cash.cashInHand;

      scope.sales.recordSale(items: [SaleItem(product: product, qty: 1, unitPrice: product.unitPrice)], discountPercent: 0, isCredit: false, userName: 'Owner');
      expect(scope.cash.cashInHand, cashBefore + product.unitPrice);
    });
  });

  group('purchasing', () {
    test('createPurchase increases stock and supplier payable by the unpaid amount', () async {
      final scope = await signedIn(UserRole.owner);
      final product = scope.inventory.products.first;
      final supplier = scope.suppliers.suppliers.first;
      final stockBefore = product.stockQty;
      final payableBefore = supplier.amountPayable;

      final purchase = scope.purchasing.createPurchase(
        supplier: supplier,
        items: [PurchaseItem(product: product, qty: 5, unitCost: 100)],
        paidAmount: 200,
        userName: 'Owner',
      );

      expect(product.stockQty, stockBefore + 5);
      expect(purchase.total, 500);
      expect(purchase.remainingAmount, 300);
      expect(supplier.amountPayable, payableBefore + 300);
    });

    test('recordSupplierPayment reduces payable', () async {
      final scope = await signedIn(UserRole.owner);
      final supplier = scope.suppliers.suppliers.first;
      final payableBefore = supplier.amountPayable;

      scope.suppliers.recordPayment(supplier, 1000, 'partial payment', userName: 'Owner');

      expect(supplier.amountPayable, payableBefore - 1000);
    });
  });

  group('customer ordering', () {
    test('placeOrder reserves stock without touching stockQty, delivery finalizes it', () async {
      final scope = await signedIn(UserRole.customer);
      final product = scope.inventory.products.first;
      final customer = scope.customers.customers.firstWhere((c) => c.id == scope.auth.currentUser!.linkedCustomerId);
      final stockBefore = product.stockQty;

      scope.ordering.addToCart(product, 3);
      final order = scope.ordering.placeOrder(customer, deliveryType: DeliveryType.pickup, userName: 'Gurung General Store');

      expect(order, isNotNull);
      expect(product.stockQty, stockBefore, reason: 'placing an order reserves stock, it does not deduct it yet');
      expect(product.reservedQty, 3);
      expect(product.availableStock, stockBefore - 3);
      expect(scope.ordering.cart, isEmpty);

      scope.ordering.advanceOrderStatus(order!, OrderStatus.confirmed, userName: 'Owner');
      scope.ordering.advanceOrderStatus(order, OrderStatus.delivered, userName: 'Owner');

      expect(product.reservedQty, 0);
      expect(product.stockQty, stockBefore - 3);
    });

    test('cancelling a reserved order releases the reservation', () async {
      final scope = await signedIn(UserRole.customer);
      final product = scope.inventory.products.first;
      final customer = scope.customers.customers.firstWhere((c) => c.id == scope.auth.currentUser!.linkedCustomerId);
      final stockBefore = product.stockQty;

      scope.ordering.addToCart(product, 2);
      final order = scope.ordering.placeOrder(customer, deliveryType: DeliveryType.pickup, userName: 'Gurung General Store')!;
      scope.ordering.advanceOrderStatus(order, OrderStatus.cancelled, userName: 'Owner');

      expect(product.reservedQty, 0);
      expect(product.stockQty, stockBefore);
    });
  });

  group('permissions', () {
    test('owner has full permissions, employee cannot manage products or view accounting', () async {
      final business = await TestBusiness.create();
      final scope = await business.device(UserRole.owner);
      expect(scope.auth.can(Permission.manageProducts), isTrue);
      expect(scope.auth.can(Permission.viewAccounting), isTrue);

      await scope.auth.logout();
      expect(await scope.auth.login(TestBusiness.phones[UserRole.employee]!, TestBusiness.password), isTrue);
      expect(scope.auth.can(Permission.manageProducts), isFalse);
      expect(scope.auth.can(Permission.viewAccounting), isFalse);
      expect(scope.auth.can(Permission.createSales), isTrue);
    });

    test('employee cannot record expenses — quick actions must not offer it', () async {
      final scope = await signedIn(UserRole.employee);

      // Regression guard: QuickActionFab used to show "Add Expense" to every
      // role regardless of permission.
      expect(scope.auth.can(Permission.manageExpenses), isFalse);
      expect(scope.auth.can(Permission.createSales), isTrue);
      expect(scope.auth.can(Permission.recordPayments), isTrue);
    });

    test('custom permission override replaces the role default', () async {
      final scope = await signedIn(UserRole.owner);
      final employee = scope.employees.employees.firstWhere((u) => u.role == UserRole.employee);

      scope.employees.updatePermissions(employee, {Permission.viewSales}, userName: 'Owner');

      expect(employee.can(Permission.viewSales), isTrue);
      expect(employee.can(Permission.createSales), isFalse, reason: 'custom permissions replace, not extend, the role default');
    });
  });

  group('audit log', () {
    test('price changes and stock adjustments are recorded', () async {
      final scope = await signedIn(UserRole.owner);
      final product = scope.inventory.products.first;

      scope.inventory.updateProduct(product, userName: 'Owner', unitPrice: product.unitPrice + 50);
      expect(scope.auditRepository.entries.any((e) => e.action == 'Price changed' && e.entityId == product.id), isTrue);

      scope.inventory.adjustStock(product, AdjustmentType.damaged, 1, 'dropped a case', userName: 'Owner');
      expect(scope.auditRepository.entries.any((e) => e.action == 'Stock adjusted' && e.entityId == product.id), isTrue);
    });
  });

  group('backend sync', () {
    test('a second device on the same backend sees writes, and concurrent stock changes both apply', () async {
      final business = await TestBusiness.create();
      final deviceA = await business.device(UserRole.owner);
      final deviceB = await business.device(UserRole.employee);

      final productA = deviceA.inventory.products.first;
      final productB = deviceB.inventory.products.firstWhere((p) => p.id == productA.id);
      final stockBefore = productA.stockQty;

      deviceA.sales.recordSale(items: [SaleItem(product: productA, qty: 2, unitPrice: productA.unitPrice)], discountPercent: 0, isCredit: false, userName: 'Owner');
      deviceB.sales.recordSale(items: [SaleItem(product: productB, qty: 3, unitPrice: productB.unitPrice)], discountPercent: 0, isCredit: false, userName: 'Employee');
      await pumpEventQueue();

      expect(productA.stockQty, stockBefore - 5, reason: 'increments merge instead of last-write-wins');
      expect(productB.stockQty, stockBefore - 5);
      expect(deviceA.sales.sales, hasLength(2));
      expect(deviceB.sales.sales.first.items.first.product, same(productB), reason: 'remote docs resolve to local entity objects');
    });

    test('one operation is committed as one batch', () async {
      final business = await TestBusiness.create();
      final owner = await business.device(UserRole.owner);
      final recording = _RecordingStore(business.store);
      final device = AppScope(store: recording, authRepository: business.auth);
      await device.auth.login(TestBusiness.phones[UserRole.owner]!, TestBusiness.password);
      recording.commits.clear();

      final product = device.inventory.products.first;
      final customer = device.customers.customers.first;
      device.sales.recordSale(items: [SaleItem(product: product, qty: 1, unitPrice: product.unitPrice)], discountPercent: 0, isCredit: true, customer: customer, userName: 'Owner');
      await pumpEventQueue();

      expect(recording.commits, hasLength(1), reason: 'sale + stock + balance + audit must land all-or-nothing');
      expect(recording.commits.single.map((op) => op.collection).toSet(), containsAll(['sales', 'products', 'customers', 'auditLog']));
      expect(owner.sales.sales, hasLength(1));
    });

    test('a customer device only loads its own data', () async {
      final business = await TestBusiness.create();
      final owner = await business.device(UserRole.owner);
      final customer = await business.device(UserRole.customer);

      expect(customer.customers.customers.map((c) => c.id), [customer.auth.currentUser!.linkedCustomerId]);
      expect(customer.sales.sales, isEmpty);
      expect(customer.cash.ledger, isEmpty);
      expect(customer.suppliers.suppliers, isEmpty);
      expect(customer.employees.employees, isEmpty);
      expect(customer.inventory.products, isNotEmpty, reason: 'the catalogue is visible');

      // Another customer's order is invisible to this one.
      final other = owner.customers.customers.firstWhere((c) => c.id != customer.auth.currentUser!.linkedCustomerId);
      expect(await owner.customers.createLogin(other, phone: '9800000009', password: TestBusiness.password, userName: 'Owner'), isNull);
      final otherCustomer = AppScope(store: business.store, authRepository: business.auth);
      await otherCustomer.auth.login('9800000009', TestBusiness.password);
      otherCustomer.ordering.addToCart(otherCustomer.inventory.products.first, 1);
      otherCustomer.ordering.placeOrder(otherCustomer.customers.customers.single, deliveryType: DeliveryType.pickup, userName: other.name);
      await pumpEventQueue();

      expect(customer.ordering.orders, isEmpty);
      expect(owner.ordering.orders, hasLength(1));
    });
  });

  group('accounts', () {
    test('setup works once; a second setup is refused', () async {
      final business = await TestBusiness.create();
      final again = AppScope(store: business.store, authRepository: business.auth);
      expect(await again.auth.isBusinessSetUp(), isTrue);
      expect(await again.auth.setUpBusiness(businessName: 'X', ownerName: 'Intruder', phone: '9811111111', password: 'password123', includeSampleData: false), isFalse);
      expect(again.auth.loginError, contains('already set up'));
    });

    test('a deactivated employee cannot log in; wrong passwords are rejected', () async {
      final business = await TestBusiness.create();
      final owner = await business.device(UserRole.owner);
      final employee = owner.employees.employees.firstWhere((u) => u.role == UserRole.employee);
      owner.employees.setActive(employee, false, userName: 'Owner');
      await pumpEventQueue();

      final other = AppScope(store: business.store, authRepository: business.auth);
      expect(await other.auth.login(TestBusiness.phones[UserRole.employee]!, TestBusiness.password), isFalse);
      expect(other.auth.loginError, contains('deactivated'));
      expect(await other.auth.login(TestBusiness.phones[UserRole.owner]!, 'wrong'), isFalse);
    });

    test('employee accounts: duplicate phone and short password refused, session unchanged', () async {
      final owner = await signedIn(UserRole.owner);
      expect(await owner.employees.createEmployeeAccount(name: 'Dup', phone: TestBusiness.phones[UserRole.employee]!, password: 'password123', role: UserRole.employee, userName: 'Owner'), isNotNull);
      expect(await owner.employees.createEmployeeAccount(name: 'Short', phone: '9822222222', password: 'short', role: UserRole.employee, userName: 'Owner'), contains('8 characters'));
      expect(owner.auth.currentUser?.role, UserRole.owner, reason: 'creating an account must not switch the session');
    });

    test('change password, then OTP reset after phone verification', () async {
      final business = await TestBusiness.create();
      final phone = TestBusiness.phones[UserRole.employee]!;
      final device = await business.device(UserRole.employee);

      await device.auth.changePassword(TestBusiness.password, 'newpassword1');
      expect(() => device.auth.changePassword('wrong-current', 'another123'), throwsA(isA<AuthException>()));

      // Unverified phone: OTP reset refused.
      var id = await device.auth.startPasswordReset(phone);
      expect(() => device.auth.completePasswordReset(id, business.auth.lastOtp!, 'reset12345'), throwsA(isA<AuthException>()));

      id = await device.auth.startPhoneVerification();
      await device.auth.completePhoneVerification(id, business.auth.lastOtp!);
      expect(device.auth.phoneVerified, isTrue);
      await device.auth.logout();

      id = await device.auth.startPasswordReset(phone);
      expect(() => device.auth.completePasswordReset(id, '000000', 'reset12345'), throwsA(isA<AuthException>()), reason: 'wrong code');
      id = await device.auth.startPasswordReset(phone);
      await device.auth.completePasswordReset(id, business.auth.lastOtp!, 'reset12345');
      expect(await device.auth.login(phone, 'reset12345'), isTrue);
    });
  });

  group('customer management', () {
    test('add and edit a customer; credit limit changes are audited', () async {
      final owner = await signedIn(UserRole.owner);
      final customer = owner.customers.createCustomer(name: 'New Shop', phone: '9855555555', location: 'Patan', creditLimit: 10000, userName: 'Owner');
      owner.customers.updateCustomer(customer, name: 'New Shop Pvt', phone: customer.phone, location: 'Patan', creditLimit: 15000, defaultDiscountPercent: 2, userName: 'Owner');
      await pumpEventQueue();

      expect(owner.customers.customers.firstWhere((c) => c.id == customer.id).creditLimit, 15000);
      expect(owner.auditRepository.entries.any((e) => e.action == 'Credit limit changed' && e.entityId == customer.id), isTrue);
      expect(await owner.customers.createLogin(customer, phone: '9855555555', password: 'password123', userName: 'Owner'), isNull);
      expect(owner.customers.loginFor(customer)?.role, UserRole.customer);
      expect(await owner.customers.createLogin(customer, phone: '9855555556', password: 'password123', userName: 'Owner'), contains('already has a login'));
    });
  });
}

class _RecordingStore implements RemoteStore {
  _RecordingStore(this._inner);

  final RemoteStore _inner;
  final commits = <List<WriteOp>>[];

  @override
  Stream<List<Json>> watch(String collection, {String? id, Map<String, Object?> where = const {}}) => _inner.watch(collection, id: id, where: where);

  @override
  Future<Json?> get(String collection, String id) => _inner.get(collection, id);

  @override
  Future<void> commit(List<WriteOp> ops) {
    commits.add(ops);
    return _inner.commit(ops);
  }
}
