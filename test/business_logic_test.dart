import 'package:flutter_test/flutter_test.dart';
import 'package:sarathigrocery/app/injection.dart';
import 'package:sarathigrocery/core/data/remote_store.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/auth_repository.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/customer_order.dart';
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
    UserRole.delivery: '9800000005',
  };

  static Future<TestBusiness> create() async {
    final business = TestBusiness();
    final owner = AppScope(store: business.store, authRepository: business.auth);
    expect(
      await owner.auth.setUpBusiness(businessName: 'Test Shop', ownerName: 'Owner', phone: phones[UserRole.owner]!, password: password, includeSampleData: true),
      isTrue,
      reason: owner.auth.loginError,
    );
    for (final role in [UserRole.accountant, UserRole.employee, UserRole.delivery]) {
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

  paymentTests();

  group('business reset', () {
    test('owner reset erases everything; setup starts fresh with the same phone', () async {
      final business = await TestBusiness.create();
      final owner = await business.device(UserRole.owner);
      final product = owner.inventory.products.first;
      owner.sales.recordSale(items: [SaleItem(product: product, qty: 1, unitPrice: product.unitPrice)], discountPercent: 0, isCredit: false, userName: 'Owner');
      await pumpEventQueue();
      expect(business.store.documentCount, greaterThan(20));

      final ownerUser = owner.auth.currentUser!;
      await expectLater(owner.settings.resetBusiness(owner: ownerUser, typedName: 'Wrong Shop', password: TestBusiness.password), throwsA(isA<AuthException>()));
      await expectLater(owner.settings.resetBusiness(owner: ownerUser, typedName: 'Test Shop', password: 'wrong-password'), throwsA(isA<AuthException>()));
      final accountant = await business.device(UserRole.accountant);
      await expectLater(accountant.settings.resetBusiness(owner: accountant.auth.currentUser!, typedName: 'Test Shop', password: TestBusiness.password), throwsA(isA<AuthException>()));

      business.store.online = false;
      await expectLater(owner.settings.resetBusiness(owner: ownerUser, typedName: 'Test Shop', password: TestBusiness.password),
          throwsA(isA<AuthException>().having((e) => e.message, 'message', contains('No internet'))));
      expect(business.store.documentCount, greaterThan(20), reason: 'nothing deleted offline');
      business.store.online = true;

      await owner.settings.resetBusiness(owner: ownerUser, typedName: 'Test Shop', password: TestBusiness.password);
      await owner.auth.logout();
      expect(business.store.documentCount, 0);

      final fresh = AppScope(store: business.store, authRepository: business.auth);
      expect(await fresh.auth.isBusinessSetUp(), isFalse);
      expect(await fresh.auth.login(TestBusiness.phones[UserRole.employee]!, TestBusiness.password), isFalse, reason: 'old staff profiles are gone');
      expect(
        await fresh.auth.setUpBusiness(businessName: 'New Shop', ownerName: 'Owner', phone: TestBusiness.phones[UserRole.owner]!, password: TestBusiness.password, includeSampleData: false),
        isTrue,
        reason: fresh.auth.loginError,
      );
      expect(fresh.inventory.products, isEmpty);
      expect(fresh.settings.current.businessName, 'New Shop');
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


void paymentTests() {
  /// Customer owes 5,000 (limit 20,000), orders exactly 5,000, and the
  /// delivery person is assigned. Returns the devices and the order.
  Future<({TestBusiness business, AppScope owner, AppScope accountant, AppScope delivery, AppScope customer, CustomerOrder order})> scenario() async {
    final business = await TestBusiness.create();
    final owner = await business.device(UserRole.owner);
    final shop = owner.customers.createCustomer(name: 'Kathmandu Kirana', phone: '9866666666', location: 'Patan', creditLimit: 20000, openingBalance: 5000, userName: 'Owner');
    expect(await owner.customers.createLogin(shop, phone: '9866666666', password: TestBusiness.password, userName: 'Owner'), isNull);
    owner.inventory.createProduct(name: 'Ghee 5L', category: 'Oil', unitPrice: 5000, stockQty: 10, reorderLevel: 1);
    await pumpEventQueue();

    final customer = AppScope(store: business.store, authRepository: business.auth);
    expect(await customer.auth.login('9866666666', TestBusiness.password), isTrue, reason: customer.auth.loginError);
    customer.ordering.addToCart(customer.inventory.products.firstWhere((p) => p.name == 'Ghee 5L'), 1);
    final placed = customer.ordering.placeOrder(customer.customers.customers.single, deliveryType: DeliveryType.delivery, address: 'Patan', userName: 'Kathmandu Kirana', userId: customer.auth.currentUser!.id)!;
    await pumpEventQueue();
    expect(placed.overCreditLimit, isFalse, reason: '5,000 owed + 5,000 order is within 20,000');

    final order = owner.ordering.orders.firstWhere((o) => o.id == placed.id);
    final deliveryUser = owner.ordering.deliverers.firstWhere((u) => u.role == UserRole.delivery);
    owner.ordering.assign(order, deliveryUser, by: owner.auth.currentUser!);
    for (final status in [OrderStatus.confirmed, OrderStatus.preparing, OrderStatus.ready]) {
      owner.ordering.advanceOrderStatus(order, status, userName: 'Owner');
    }
    await pumpEventQueue();

    final delivery = await business.device(UserRole.delivery);
    final accountant = await business.device(UserRole.accountant);
    return (business: business, owner: owner, accountant: accountant, delivery: delivery, customer: customer, order: order);
  }

  group('payment verification', () {
    test('customer pays 7,000 at the door on a 5,000 order: 5,000 settles the order, 2,000 the old balance', () async {
      final s = await scenario();
      final order = s.delivery.ordering.orders.single;
      expect(s.delivery.ordering.deliveryCodeFor(order), isNull, reason: 'the delivery person must not be able to see the code');
      final code = s.customer.ordering.deliveryCodeFor(s.customer.ordering.orders.single)!;

      s.delivery.ordering.advanceOrderStatus(order, OrderStatus.outForDelivery, userName: 'Delivery', userId: s.delivery.auth.currentUser!.id);
      final result = await s.delivery.ordering.deliverAndCollect(order, amount: 7000, method: PaymentMethod.cash, deliveryCode: code, collector: s.delivery.auth.currentUser!);
      await pumpEventQueue();

      final payment = result!;
      expect(payment.appliedToOrder, 5000);
      expect(payment.appliedToPreviousBalance, 2000);
      expect(payment.balanceAfter, 3000);
      expect(payment.confirmedByCode, isTrue);
      expect(payment.isPendingHandover, isTrue, reason: 'cash is with the delivery person until the shop counts it');

      final ownerCustomer = s.owner.customers.customers.firstWhere((c) => c.name == 'Kathmandu Kirana');
      expect(ownerCustomer.outstandingBalance, 3000);
      final statement = s.owner.payments.statementFor(ownerCustomer);
      expect(statement.balanced, isTrue);
      final invoice = s.owner.sales.sales.firstWhere((x) => x.orderId == order.id);
      expect(statement.dueFor(invoice), 0, reason: 'the order is fully paid');
      expect(statement.openingPaid, 2000);

      // The customer sees the same thing on their own device.
      final customerStatement = s.customer.payments.statementFor(s.customer.customers.customers.single);
      expect(customerStatement.expectedBalance, 3000);
      expect(customerStatement.balanced, isTrue);

      // Cash only reaches the books when someone else counts it in.
      final cashBefore = s.accountant.cash.cashInHand;
      final pending = s.accountant.payments.pendingHandover.single;
      s.accountant.payments.settle(pending, 7000, receiver: s.accountant.auth.currentUser!);
      await pumpEventQueue();
      expect(s.accountant.cash.cashInHand, cashBefore + 7000);
      expect(s.delivery.payments.payments.single.isSettled, isTrue);
    });

    test('short handover is recorded against the collector and flagged to the owner', () async {
      final s = await scenario();
      final order = s.delivery.ordering.orders.single;
      s.delivery.ordering.advanceOrderStatus(order, OrderStatus.outForDelivery, userName: 'Delivery');
      await s.delivery.ordering.deliverAndCollect(order, amount: 7000, method: PaymentMethod.cash, collector: s.delivery.auth.currentUser!);
      await pumpEventQueue();

      s.accountant.payments.settle(s.accountant.payments.pendingHandover.single, 6500, receiver: s.accountant.auth.currentUser!);
      await pumpEventQueue();

      expect(s.owner.payments.shortfalls.single.shortfall, 500);
      expect(s.owner.notificationRepository.notificationsFor(s.owner.auth.currentUser!).any((n) => n.title == 'Cash shortfall'), isTrue);
      expect(s.owner.customers.customers.firstWhere((c) => c.name == 'Kathmandu Kirana').outstandingBalance, 3000, reason: 'the customer paid in full; the gap is not theirs');
    });

    test('nobody receives their own collection; the delivery role cannot receive at all', () async {
      final s = await scenario();
      final order = s.delivery.ordering.orders.single;
      s.delivery.ordering.advanceOrderStatus(order, OrderStatus.outForDelivery, userName: 'Delivery');
      await s.delivery.ordering.deliverAndCollect(order, amount: 1000, method: PaymentMethod.cash, collector: s.delivery.auth.currentUser!);
      final payment = s.delivery.payments.payments.single;
      expect(() => s.delivery.payments.settle(payment, 1000, receiver: s.delivery.auth.currentUser!), throwsA(isA<PaymentException>()));

      // An employee collects at the counter: waits for handover; the accountant's own counter collection settles at once.
      final employee = await s.business.device(UserRole.employee);
      final shop = employee.customers.customers.firstWhere((c) => c.name == 'Kathmandu Kirana');
      expect(employee.payments.record(shop, 500, method: PaymentMethod.cash, collector: employee.auth.currentUser!).isSettled, isFalse);
      final accountantShop = s.accountant.customers.customers.firstWhere((c) => c.name == 'Kathmandu Kirana');
      expect(s.accountant.payments.record(accountantShop, 500, method: PaymentMethod.cash, collector: s.accountant.auth.currentUser!).isSettled, isTrue);
      expect(() => s.accountant.payments.record(accountantShop, 500, method: PaymentMethod.wallet, collector: s.accountant.auth.currentUser!), throwsA(isA<PaymentException>()), reason: 'non-cash needs a reference');
    });

    test('delivered on credit, later paid at the counter: oldest balance is paid first', () async {
      final s = await scenario();
      final order = s.delivery.ordering.orders.single;
      s.delivery.ordering.advanceOrderStatus(order, OrderStatus.outForDelivery, userName: 'Delivery');
      final result = await s.delivery.ordering.deliverAndCollect(order, amount: 0, method: PaymentMethod.cash, collector: s.delivery.auth.currentUser!);
      expect(result, isNull);
      await pumpEventQueue();

      final shop = s.accountant.customers.customers.firstWhere((c) => c.name == 'Kathmandu Kirana');
      expect(shop.outstandingBalance, 10000, reason: 'the invoice goes on the balance at delivery');
      s.accountant.payments.record(shop, 6000, method: PaymentMethod.bank, reference: 'NIC-1234', collector: s.accountant.auth.currentUser!);
      await pumpEventQueue();

      final statement = s.accountant.payments.statementFor(shop);
      final invoice = s.accountant.sales.sales.firstWhere((x) => x.orderId == order.id);
      expect(statement.openingPaid, 5000, reason: 'the old 5,000 is paid off first');
      expect(statement.dueFor(invoice), 4000);
      expect(shop.outstandingBalance, 4000);
      expect(statement.balanced, isTrue);
    });

    test('customer confirms or disputes; owner reverses a wrong payment and the books still balance', () async {
      final s = await scenario();
      final employee = await s.business.device(UserRole.employee);
      final shop = employee.customers.customers.firstWhere((c) => c.name == 'Kathmandu Kirana');
      employee.payments.record(shop, 1000, method: PaymentMethod.cash, collector: employee.auth.currentUser!);
      employee.payments.record(shop, 2000, method: PaymentMethod.cash, collector: employee.auth.currentUser!);
      await pumpEventQueue();

      final customerUser = s.customer.auth.currentUser!;
      final mine = s.customer.payments.payments;
      s.customer.payments.confirm(mine[0], customerUser: customerUser);
      s.customer.payments.dispute(mine[1], 'I paid 200, not 2,000', customerUser: customerUser);
      expect(() => s.customer.payments.confirm(mine[1], customerUser: customerUser), throwsA(isA<PaymentException>()));
      await pumpEventQueue();
      expect(s.owner.payments.disputed.single.disputeNote, contains('200'));

      final disputed = s.owner.payments.disputed.single;
      expect(() => s.accountant.payments.reverse(disputed, 'x', owner: s.accountant.auth.currentUser!), throwsA(isA<PaymentException>()), reason: 'owner only');
      s.owner.payments.reverse(disputed, 'Recorded wrong amount', owner: s.owner.auth.currentUser!);
      await pumpEventQueue();

      final ownerShop = s.owner.customers.customers.firstWhere((c) => c.name == 'Kathmandu Kirana');
      expect(ownerShop.outstandingBalance, 4000);
      expect(s.owner.payments.statementFor(ownerShop).balanced, isTrue);
      expect(s.customer.payments.statementFor(s.customer.customers.customers.single).expectedBalance, 4000);
    });

    test('a balance changed outside sales and payments is detected', () async {
      final s = await scenario();
      final shop = s.owner.customers.customers.firstWhere((c) => c.name == 'Kathmandu Kirana');
      s.owner.customers.repository.applyBalanceChange(shop, -1500); // bypasses the payment flow
      final statement = s.owner.payments.statementFor(shop);
      expect(statement.balanced, isFalse);
      expect(statement.unexplainedDifference, -1500);
    });

    test('orders past the credit limit are flagged', () async {
      final s = await scenario();
      final product = s.customer.inventory.products.firstWhere((p) => p.name == 'Ghee 5L');
      s.customer.ordering.addToCart(product, 3); // 5,000 owed + 5,000 open + 15,000 > 20,000
      final order = s.customer.ordering.placeOrder(s.customer.customers.customers.single, deliveryType: DeliveryType.pickup, userName: 'x', userId: s.customer.auth.currentUser!.id)!;
      expect(order.overCreditLimit, isTrue);
    });

    test('no connection: delivery is refused, nothing is recorded, screens roll back', () async {
      final s = await scenario();
      final order = s.delivery.ordering.orders.single;
      s.delivery.ordering.advanceOrderStatus(order, OrderStatus.outForDelivery, userName: 'Delivery');
      await pumpEventQueue();
      final shop = s.delivery.customers.customers.firstWhere((c) => c.name == 'Kathmandu Kirana');
      final stock = order.items.single.product.stockQty;

      s.business.store.online = false;
      await expectLater(
        s.delivery.ordering.deliverAndCollect(order, amount: 7000, method: PaymentMethod.cash, collector: s.delivery.auth.currentUser!),
        throwsA(isA<PaymentException>().having((e) => e.message, 'message', contains('No internet'))),
      );
      await pumpEventQueue();

      expect(order.status, OrderStatus.outForDelivery, reason: 'local copy rolled back');
      expect(shop.outstandingBalance, 5000);
      expect(order.items.single.product.stockQty, stock);
      expect(s.delivery.payments.payments, isEmpty);
      expect(s.owner.sales.sales.where((x) => x.orderId == order.id), isEmpty, reason: 'nothing reached the server');
    });

    test('wrong code: refused and rolled back; after 5 tries the order locks until the owner unlocks it', () async {
      final s = await scenario();
      final order = s.delivery.ordering.orders.single;
      s.delivery.ordering.advanceOrderStatus(order, OrderStatus.outForDelivery, userName: 'Delivery');
      await pumpEventQueue();
      // Stand-in for the server rule: refuse "code verified" unless the last
      // registered code is the real one.
      final realCode = s.customer.ordering.deliveryCodeFor(s.customer.ordering.orders.single)!;
      String? registered;
      s.business.store.rejectIf = (ops) {
        for (final op in ops) {
          if (op is PutOp && op.collection == 'codeChecks' && op.data.containsKey('lastCode')) registered = op.data['lastCode'];
          if (op is PutOp && op.collection == 'codeChecks' && op.data['verified'] == true && registered != realCode) return true;
        }
        return false;
      };
      final me = s.delivery.auth.currentUser!;

      for (var i = 1; i <= 5; i++) {
        await expectLater(
          s.delivery.ordering.deliverAndCollect(order, amount: 7000, method: PaymentMethod.cash, deliveryCode: '00000$i', collector: me),
          throwsA(isA<PaymentException>().having((e) => e.message, 'message', contains('${5 - i} attempt'))),
        );
        await pumpEventQueue();
        expect(order.status, OrderStatus.outForDelivery);
      }
      await expectLater(
        s.delivery.ordering.deliverAndCollect(order, amount: 7000, method: PaymentMethod.cash, deliveryCode: realCode, collector: me),
        throwsA(isA<PaymentException>().having((e) => e.message, 'message', contains('Too many'))),
      );

      s.owner.ordering.resetCodeAttempts(s.owner.ordering.orders.firstWhere((o) => o.id == order.id), by: s.owner.auth.currentUser!);
      await pumpEventQueue();
      final payment = await s.delivery.ordering.deliverAndCollect(order, amount: 7000, method: PaymentMethod.cash, deliveryCode: realCode, collector: me);
      expect(payment!.confirmedByCode, isTrue);
      expect(order.status, OrderStatus.delivered);
    });

    test('reversing a payment already in the till refunds it out of the till', () async {
      final s = await scenario();
      final shop = s.accountant.customers.customers.firstWhere((c) => c.name == 'Kathmandu Kirana');
      final cashBefore = s.accountant.cash.cashInHand;
      s.accountant.payments.record(shop, 2000, method: PaymentMethod.cash, collector: s.accountant.auth.currentUser!);
      await pumpEventQueue();
      expect(s.accountant.cash.cashInHand, cashBefore + 2000);

      s.owner.payments.reverse(s.owner.payments.payments.single, 'Wrong customer', owner: s.owner.auth.currentUser!);
      await pumpEventQueue();
      expect(s.owner.cash.cashInHand, cashBefore, reason: 'refund entry takes it back out');
      final ownerShop = s.owner.customers.customers.firstWhere((c) => c.name == 'Kathmandu Kirana');
      expect(ownerShop.outstandingBalance, 5000);
      expect(s.owner.payments.statementFor(ownerShop).balanced, isTrue);
    });

    test('bank, wallet and cheque money lands in those accounts; deposits move cash to bank', () async {
      final s = await scenario();
      final shop = s.accountant.customers.customers.firstWhere((c) => c.name == 'Kathmandu Kirana');
      final a = s.accountant.auth.currentUser!;
      s.accountant.payments.record(shop, 1000, method: PaymentMethod.bank, reference: 'NIC-1', collector: a);
      s.accountant.payments.record(shop, 500, method: PaymentMethod.wallet, reference: 'ESEWA-9', collector: a);
      s.accountant.payments.record(shop, 300, method: PaymentMethod.cheque, reference: 'CHQ-7', collector: a);
      s.accountant.payments.record(shop, 800, method: PaymentMethod.cash, collector: a);
      s.accountant.cash.addBankDeposit(600, '');
      await pumpEventQueue();

      expect(s.accountant.cash.bankBalance, 1000 + 300 + 600);
      expect(s.accountant.cash.walletBalance, 500);
      expect(s.accountant.cash.cashInHand, 800 - 600);
    });

    test('orders delivered before invoicing existed can be billed by the owner', () async {
      final s = await scenario();
      final order = s.owner.ordering.orders.single;
      // A delivered order with no invoice, as older versions left them.
      await s.business.store.commit([PutOp('orders', order.id, {'status': 'delivered'})]);
      await pumpEventQueue();
      expect(s.owner.ordering.uninvoicedDeliveries.map((o) => o.id), [order.id]);

      expect(s.owner.ordering.invoiceUninvoicedDeliveries(by: s.owner.auth.currentUser!), 1);
      await pumpEventQueue();
      final shop = s.owner.customers.customers.firstWhere((c) => c.name == 'Kathmandu Kirana');
      expect(shop.outstandingBalance, 10000);
      expect(s.owner.ordering.uninvoicedDeliveries, isEmpty);
      expect(s.owner.payments.statementFor(shop).balanced, isTrue);
    });

    test('customers and delivery staff never receive cost prices; audit entries carry the author', () async {
      final s = await scenario();
      final staffGhee = s.owner.inventory.products.firstWhere((p) => p.name == 'Basmati Rice 25kg');
      expect(staffGhee.purchasePrice, 2800);
      for (final device in [s.customer, s.delivery]) {
        expect(device.inventory.products.firstWhere((p) => p.name == 'Basmati Rice 25kg').purchasePrice, 0);
      }
      expect(s.owner.auditRepository.entries.first.userId, isNotNull);
    });

    test('delivery staff only load their assigned orders and own collections', () async {
      final s = await scenario();
      expect(s.delivery.ordering.orders, hasLength(1));
      expect(s.delivery.sales.sales, isEmpty);
      expect(s.delivery.cash.ledger, isEmpty);
      expect(s.delivery.customers.customers, isNotEmpty, reason: 'needs address and balance to collect');
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
  Future<List<String>> listIds(String collection) => _inner.listIds(collection);

  @override
  Future<void> commit(List<WriteOp> ops, {bool requireOnline = false}) {
    commits.add(ops);
    return _inner.commit(ops, requireOnline: requireOnline);
  }
}