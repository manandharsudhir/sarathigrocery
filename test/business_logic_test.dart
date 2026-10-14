import 'package:flutter_test/flutter_test.dart';
import 'package:sarathigrocery/app/injection.dart';
import 'package:sarathigrocery/app/accountant_export.dart';
import 'package:sarathigrocery/app/shop_export.dart';
import 'package:sarathigrocery/features/accounting/presentation/pages/accounting_screen.dart';
import 'package:sarathigrocery/features/accounting/domain/books.dart';
import 'package:sarathigrocery/features/accounting/domain/entities/accounts.dart';
import 'package:sarathigrocery/core/utils/bs_date.dart';
import 'package:sarathigrocery/features/accounting/presentation/pages/vat_books_screen.dart';
import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/core/data/remote_store.dart';
import 'package:sarathigrocery/core/widgets/signature_pad.dart';
import 'package:sarathigrocery/features/customers/presentation/pdf/payment_documents.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/auth_repository.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/customer_order.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/adjustment_type.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product_pack.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product_unit.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/unit_setup.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_item.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/delivery_type.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_status.dart';
import 'package:sarathigrocery/features/purchasing/domain/entities/purchase_item.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_item.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_status.dart';
import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/settings/domain/entities/business_settings.dart';

import 'sign_up.dart';

/// A freshly set-up business on a shared in-memory backend, with one login
/// per staff role, plus a staff member who can handle cash & accounts.
class TestBusiness {
  final store = InMemoryRemoteStore();
  final auth = InMemoryAuthRepository();

  static const password = 'password123';
  static const phones = {
    UserRole.owner: '9800000001',
    UserRole.employee: '9800000003',
    UserRole.delivery: '9800000005',
  };
  static const cashierPhone = '9800000002';

  /// The shop's id (all its data lives under `shops/<shopId>/`).
  late final String shopId;

  /// [safeguards]: switch every Settings → Safeguard on (the strict flows
  /// most payment tests cover); a new shop starts with all off.
  static Future<TestBusiness> create({bool safeguards = true}) async {
    final business = TestBusiness();
    final owner = AppScope(store: business.store, authRepository: business.auth);
    expect(
      await signUp(owner, business.auth, phone: phones[UserRole.owner]!, password: password, sampleData: true),
      isTrue,
      reason: owner.auth.loginError,
    );
    business.shopId = (await business.store.get('accounts', owner.auth.currentUser!.id))!['shopIds'].single;
    for (final role in [UserRole.employee, UserRole.delivery]) {
      expect((await owner.employees.createEmployeeAccount(name: role.name, email: testEmail(phones[role]!), phone: phones[role]!, password: password, role: role, userName: 'Owner')).error, isNull);
    }
    expect((await owner.employees.createEmployeeAccount(name: 'cashier', email: testEmail(cashierPhone), phone: cashierPhone, password: password, role: UserRole.employee, userName: 'Owner')).error, isNull);
    owner.employees.setCashAccess(owner.employees.employees.firstWhere((u) => u.phone == cashierPhone), true, userName: 'Owner');
    if (safeguards) owner.settings.enableAllSafeguards();
    await pumpEventQueue();
    return business;
  }

  /// A new "device" signed in as [role].
  Future<AppScope> device(UserRole role) => _login(phones[role]!);

  /// A new device signed in as the staff member with cash & accounts.
  Future<AppScope> cashier() => _login(cashierPhone);

  Future<AppScope> _login(String phone) async {
    final scope = AppScope(store: store, authRepository: auth);
    expect(await scope.auth.login(testEmail(phone), password), isTrue, reason: scope.auth.loginError);
    return scope;
  }
}

Future<AppScope> signedIn(UserRole role) async => (await TestBusiness.create()).device(role);

String testSignature() => const Signature([
      [Offset(10, 10), Offset(500, 400), Offset(900, 120)],
    ]).encode();

void main() {
  test('product search matches name, category or SKU, ignoring case', () {
    final p = Product(id: 'P1', name: 'Basmati Rice', category: 'Grains', unitPrice: 100, stockQty: 1, reorderLevel: 0, sku: 'BR-5');
    expect(['', 'rice', 'GRAIN', 'br-5', ' rice '].every(p.matches), isTrue);
    expect(p.matches('oil'), isFalse);
  });

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

      scope.sales.recordSale(items: [SaleItem(product: product, qty: 1, unitPrice: product.unitPrice)], isCredit: false, userName: 'Owner');
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

  group('ordering', () {
    test('placeOrderFor reserves stock without touching stockQty, delivery finalizes it', () async {
      final scope = await signedIn(UserRole.employee);
      final product = scope.inventory.products.first;
      final customer = scope.customers.customers.first;
      final stockBefore = product.stockQty;

      final order = scope.ordering.placeOrderFor(customer, atMinimum({product: 3}), deliveryType: DeliveryType.pickup, staff: scope.auth.currentUser!);

      expect(order, isNotNull);
      expect(product.stockQty, stockBefore, reason: 'placing an order reserves stock, it does not deduct it yet');
      expect(product.reservedQty, 3);
      expect(product.availableStock, stockBefore - 3);

      scope.ordering.advanceOrderStatus(order!, OrderStatus.confirmed, userName: 'Owner');
      scope.ordering.advanceOrderStatus(order, OrderStatus.delivered, userName: 'Owner');

      expect(product.reservedQty, 0);
      expect(product.stockQty, stockBefore - 3);
    });

    test('cancelling a reserved order releases the reservation', () async {
      final scope = await signedIn(UserRole.employee);
      final product = scope.inventory.products.first;
      final customer = scope.customers.customers.first;
      final stockBefore = product.stockQty;

      final order = scope.ordering.placeOrderFor(customer, atMinimum({product: 2}), deliveryType: DeliveryType.pickup, staff: scope.auth.currentUser!)!;
      scope.ordering.advanceOrderStatus(order, OrderStatus.cancelled, userName: 'Owner');

      expect(product.reservedQty, 0);
      expect(product.stockQty, stockBefore);
    });
  });

  group('packs and minimum prices', () {
    // Sugar counted in kg, sold loose or by the 50 kg sack.
    Product sugar(AppScope owner) => owner.inventory.createProduct(
          name: 'Sugar',
          category: 'General',
          unit: ProductUnit.kg,
          unitPrice: 100,
          purchasePrice: 90,
          packs: const [ProductPack(label: 'sack', size: 50, price: 4800)],
          stockQty: 500,
          reorderLevel: 50,
        );

    test('a sack and loose kg come out of one stock; cost is fixed at sale time', () async {
      final owner = await signedIn(UserRole.owner);
      final p = sugar(owner);
      final sale = owner.sales.recordSale(
        items: [SaleItem(product: p, qty: 1, unitPrice: 4900, unit: 'sack', size: 50), SaleItem(product: p, qty: 2.5, unitPrice: 100)],
        isCredit: false,
        userName: 'Owner',
      );
      expect(p.stockQty, 447.5);
      expect(p.describeQty(p.stockQty), '447.5 kg (8 sack)');
      expect(sale.total, 4900 + 250);
      expect(sale.costOfGoods, 50 * 90 + 2.5 * 90);

      owner.inventory.updateProduct(p, userName: 'Owner', purchasePrice: 200);
      expect(sale.costOfGoods, 50 * 90 + 2.5 * 90, reason: 'a later cost change leaves past profit alone');
      owner.sales.cancelSale(sale, 'test', userName: 'Owner');
      expect(p.stockQty, 500);
    });

    test('below minimum: refused for staff, allowed and reported for the owner, grantable to staff', () async {
      final business = await TestBusiness.create();
      final owner = await business.device(UserRole.owner);
      sugar(owner);
      await pumpEventQueue();
      final staff = await business.device(UserRole.employee);
      final p = staff.inventory.products.firstWhere((p) => p.name == 'Sugar');
      final cheapSack = [SaleItem(product: p, qty: 1, unitPrice: 4700, unit: 'sack', size: 50)];
      final staffUser = staff.auth.currentUser!;

      expect(() => staff.sales.recordSale(items: cheapSack, isCredit: false, userName: staffUser.name), throwsA(isA<BelowMinimumPriceException>()));
      final customer = staff.customers.customers.first;
      expect(() => staff.ordering.placeOrderFor(customer, [OrderItem(product: p, qty: 1, price: 4700, unit: 'sack', size: 50)], deliveryType: DeliveryType.pickup, staff: staffUser),
          throwsA(isA<BelowMinimumPriceException>()));
      expect(p.stockQty, 500);
      expect(p.reservedQty, 0);
      // Above the minimum is always fine.
      staff.sales.recordSale(items: [SaleItem(product: p, qty: 1, unitPrice: 5000, unit: 'sack', size: 50)], isCredit: false, userName: staffUser.name);

      final ownerSugar = owner.inventory.products.firstWhere((x) => x.name == 'Sugar');
      owner.sales.recordSale(items: [SaleItem(product: ownerSugar, qty: 1, unitPrice: 4700, unit: 'sack', size: 50)], isCredit: false, userName: 'Owner', allowBelowMinimum: true);
      expect(owner.auditRepository.entries.where((e) => e.action == 'Sold below minimum price'), hasLength(1));
      expect(owner.notificationRepository.notificationsFor(owner.auth.currentUser!).any((n) => n.title == 'Sold below minimum price'), isTrue);

      final staffProfile = owner.employees.employees.firstWhere((u) => u.id == staffUser.id);
      owner.employees.updatePermissions(staffProfile, {...staffProfile.permissions, Permission.sellBelowMinimum}, userName: 'Owner');
      expect(staffProfile.can(Permission.sellBelowMinimum), isTrue);
      expect(UserRole.values.where((r) => defaultRolePermissions[r]!.contains(Permission.sellBelowMinimum)), [UserRole.owner]);
    });

    test('a pack name used twice gets its size added; a true duplicate is refused', () {
      const sack50 = ProductPack(label: 'sack', size: 50, price: 4800);
      const sack25 = ProductPack(label: 'sack', size: 25, price: 2450);
      const box = ProductPack(label: 'box', size: 10, price: 1000);
      expect([for (final p in withUniqueLabels([sack50, box], 'kg')) p.label], ['sack', 'box']);
      final named = withUniqueLabels([sack50, sack25, box], 'kg');
      expect([for (final p in named) p.label], ['sack 50kg', 'sack 25kg', 'box']);
      expect([for (final p in named) packNameOf(p.label, p.size, 'kg')], ['sack', 'sack', 'box']);
      expect(packNameOf('bori', 40, 'kg'), isNull);
      expect(() => withUniqueLabels([sack50, sack50], 'kg'), throwsArgumentError);
    });

    test('units entered against a main unit: the smallest becomes the counting unit', () {
      // Flour: main unit sack; 1 sack = 60 kg; sold by sack or kg.
      final flour = planUnits('sack', 4800, [(name: 'kg', perPrimary: 60, bigger: false, price: 85)]);
      expect(flour.base, 'kg');
      expect(flour.basePrice, 85);
      expect(flour.primarySize, 60);
      expect([for (final k in flour.packs) (k.label, k.size, k.price)], [('sack', 60.0, 4800.0)]);

      // Oil: main unit bottle; 1 box = 12 bottles; 1 crate = 4 boxes.
      final oil = planUnits('bottle', 320, [(name: 'box', perPrimary: 12, bigger: true, price: 3700), (name: 'crate', perPrimary: 48, bigger: true, price: 14500)]);
      expect(oil.base, 'bottle');
      expect([for (final k in oil.packs) k.size], [12, 48]);

      // A unit between: main unit box of 12 pieces, with a half box.
      final half = planUnits('box', 120, [(name: 'piece', perPrimary: 12, bigger: false, price: 11), (name: 'Other half', perPrimary: 2, bigger: false, price: 61)]);
      expect(half.base, 'piece');
      expect([for (final k in half.packs) (k.label, k.size)], [('box', 12.0), ('Other half', 6.0)]);

      expect(() => planUnits('sack', 1, [(name: 'kg', perPrimary: 0, bigger: false, price: 1)]), throwsArgumentError);
      expect(() => planUnits('sack', 1, [(name: 'sack', perPrimary: 2, bigger: true, price: 1)]), throwsArgumentError);
      expect(baseUnitFor('kg').unit, ProductUnit.kg);
      expect(baseUnitFor('bori'), (unit: ProductUnit.custom, custom: 'bori'));
    });

    test('a product kept in sacks shows stock in sacks; sales start in its selling unit', () async {
      final owner = await signedIn(UserRole.owner);
      final plan = planUnits('sack', 4800, [(name: 'kg', perPrimary: 60, bigger: false, price: 85)]);
      final flour = owner.inventory.createProduct(
        name: 'Flour',
        category: 'General',
        unit: baseUnitFor(plan.base).unit,
        unitPrice: plan.basePrice,
        purchasePrice: 4500 / plan.primarySize,
        packs: plan.packs,
        stockQty: 10 * plan.primarySize,
        reorderLevel: 2 * plan.primarySize,
        primaryUnit: 'sack',
        saleUnit: '',
      );
      expect(flour.describeQty(flour.stockQty), '10 sack (600 kg)');
      expect(flour.primary.label, 'sack');
      expect(flour.sellUnit(flour.saleUnit).label, 'kg');
      owner.sales.recordSale(items: [SaleItem(product: flour, qty: 30, unitPrice: 85, unit: 'kg')], isCredit: false, userName: 'Owner');
      expect(flour.describeQty(flour.stockQty), '9.5 sack (570 kg)');
    });

    test('a product sold before its first purchase is flagged until a purchase gives it a cost', () async {
      final owner = await signedIn(UserRole.owner);
      final p = owner.inventory.createProduct(name: 'New tea', category: 'General', unitPrice: 300, stockQty: 0, reorderLevel: 0);
      expect(p.purchasePrice, 0);
      owner.sales.recordSale(items: [SaleItem(product: p, qty: 1, unitPrice: 300)], isCredit: false, userName: 'Owner');
      expect(owner.accounting.salesWithoutCost, hasLength(1));
      owner.purchasing.createPurchase(supplier: owner.suppliers.suppliers.first, items: [PurchaseItem(product: p, qty: 10, unitCost: 200)], userName: 'Owner');
      expect(p.purchasePrice, 200, reason: 'stock was at or below zero: cost restarts at the purchase price');
      expect(owner.accounting.salesWithoutCost, isEmpty, reason: 'the first purchase gives the early sale its cost');
      owner.accounting.postMissingCosts();
      expect(owner.accounting.statements.balances()[Acc.cogs], 200);
      for (final c in owner.accounting.checks) {
        expect(c.books, closeTo(c.records, 0.01), reason: c.label);
      }
    });

    test('without a minimum price the cost is the floor; with neither, it cannot be sold', () async {
      final business = await TestBusiness.create();
      final owner = await business.device(UserRole.owner);
      final me = owner.auth.currentUser!;
      final p = owner.inventory.createProduct(name: 'Ghee', category: 'General', unitPrice: 0, stockQty: 0, reorderLevel: 0);
      expect(p.isUnpriced('piece'), isTrue);
      expect(() => owner.sales.recordSale(items: [SaleItem(product: p, qty: 1, unitPrice: 999)], isCredit: false, userName: 'Owner', allowBelowMinimum: true),
          throwsA(isA<UnpricedProductException>()), reason: 'not even the owner: there is no price or cost');
      expect(() => owner.ordering.placeOrderFor(owner.customers.customers.first, atMinimum({p: 1}), deliveryType: DeliveryType.pickup, staff: me),
          throwsA(isA<UnpricedProductException>()));

      owner.purchasing.createPurchase(supplier: owner.suppliers.suppliers.first, items: [PurchaseItem(product: p, qty: 5, unitCost: 1000)], userName: 'Owner');
      expect(p.floorFor('piece'), 1000, reason: 'cost is the floor until a minimum is set');
      expect(() => owner.sales.recordSale(items: [SaleItem(product: p, qty: 1, unitPrice: 990)], isCredit: false, userName: 'Owner'),
          throwsA(isA<BelowMinimumPriceException>()));
      owner.sales.recordSale(items: [SaleItem(product: p, qty: 1, unitPrice: 1000)], isCredit: false, userName: 'Owner');

      owner.purchasing.notifyPricesNeeded([p], userName: 'Owner');
      expect(owner.notificationRepository.notificationsFor(me).any((n) => n.title == 'Set selling prices'), isTrue);
      expect(suggestedPrice(1000, 10), 1100);
      expect(suggestedPrice(333, 10), 367, reason: 'rounded up to a rupee');
    });

    test('buying in sacks adds kg to stock and records the cost per kg', () async {
      final owner = await signedIn(UserRole.owner);
      final p = sugar(owner);
      owner.purchasing.createPurchase(
        supplier: owner.suppliers.suppliers.first,
        items: [PurchaseItem(product: p, qty: 2, unitCost: 4600, unit: 'sack', size: 50)],
        userName: 'Owner',
      );
      expect(p.stockQty, 600);
      expect(p.purchasePrice, closeTo((500 * 90 + 100 * 92) / 600, 1e-9), reason: 'weighted average cost per kg');
    });

    test('a returned-goods adjustment puts stock back; damaged takes it out', () async {
      final owner = await signedIn(UserRole.owner);
      final p = sugar(owner);
      owner.inventory.adjustStock(p, AdjustmentType.damaged, 1.5, 'torn sack', userName: 'Owner');
      owner.inventory.adjustStock(p, AdjustmentType.returned, 10, 'customer returned', userName: 'Owner');
      expect(p.stockQty, 508.5);
    });
  });

  group('accounting', () {
    void expectBalanced(AppScope scope) {
      for (final c in scope.accounting.checks) {
        expect(c.books, closeTo(c.records, 0.01), reason: '${c.label}: journal vs records');
      }
      final b = scope.accounting.statements.balances();
      expect(b.values.fold(0.0, (s, v) => s + v), closeTo(0, 0.01), reason: 'trial balance');
      expect(scope.accounting.statements.balanceSheet(DateTime.now()).balanced, isTrue);
    }

    test('a full trading day keeps every account in step with the records', () async {
      final s = await TestBusiness.create(safeguards: true);
      final owner = await s.device(UserRole.owner);
      final cashier = await s.cashier();
      final user = owner.auth.currentUser!;
      owner.accounting.saveSetup(owners: const [OwnerShare('Owner', 100)], by: user);
      owner.cash.capitalIn('Owner', 200000, 'cash', userName: 'Owner');
      owner.cash.transfer('cash', 'bank', 50000, 'to bank', userName: 'Owner');

      final rice = owner.inventory.products.first;
      final customer = owner.customers.customers.first;
      owner.purchasing.createPurchase(supplier: owner.suppliers.suppliers.first, items: [PurchaseItem(product: rice, qty: 10, unitCost: 2900)], paidAmount: 20000, userName: 'Owner', account: 'bank');
      owner.sales.recordSale(items: [SaleItem(product: rice, qty: 2, unitPrice: rice.unitPrice)], isCredit: false, userName: 'Owner', account: 'wallet');
      final credit = owner.sales.recordSale(items: [SaleItem(product: rice, qty: 1, unitPrice: rice.unitPrice + 100)], isCredit: true, customer: customer, userName: 'Owner');
      owner.sales.cancelSale(credit, 'wrong customer', userName: 'Owner');
      owner.cash.addExpense('Rent', 15000, 'October', createdByName: 'Owner', account: 'bank');
      owner.cash.otherPayment(8000, 'cash', 'shelves', userName: 'Owner');
      owner.cash.drawing('Owner', 2000, 'cash', 'lunch', userName: 'Owner');
      expect(() => owner.cash.drawingReturned('Owner', 2500, 'cash', '', userName: 'Owner'), throwsA(isA<AccountingException>()));
      owner.cash.drawingReturned('Owner', 500, 'bank', 'paid back', userName: 'Owner');
      owner.cash.loanReceived('NIC Asia', 100000, 'bank', userName: 'Owner');
      owner.cash.loanRepaid('NIC Asia', 10000, 'bank', userName: 'Owner');
      owner.inventory.adjustStock(rice, AdjustmentType.damaged, 1, 'torn', userName: 'Owner');
      owner.inventory.updateProduct(rice, userName: 'Owner', purchasePrice: rice.purchasePrice + 10);
      owner.suppliers.recordPayment(owner.suppliers.suppliers.first, 1000, '', userName: 'Owner', account: 'cash');
      final paid = owner.payments.record(customer, 3000, method: PaymentMethod.wallet, reference: 'WAL-1', collector: user);
      owner.payments.reverse(paid, 'wrong customer', owner: user);
      final cashPaid = cashier.payments.record(cashier.customers.customers.first, 1200, method: PaymentMethod.cash, collector: cashier.auth.currentUser!);
      expect(cashPaid.isSettled, isTrue);
      owner.purchasing.recordPurchaseReturn(owner.suppliers.suppliers.first, rice, 1, 'bad', userName: 'Owner');
      owner.cash.dividend(1000, 'cash', userName: 'Owner');
      await pumpEventQueue();

      final fresh = await s.device(UserRole.owner);
      expectBalanced(fresh);
      expect(fresh.accounting.booksBalanced, isTrue);
      final pl = fresh.accounting.statements.profitAndLoss(DateTime.now().subtract(const Duration(days: 1)), DateTime.now());
      expect(pl.costs[Acc.expense('Rent')], 15000);
      expect(fresh.accounting.statements.balanceSheet(DateTime.now()).liabilities[Acc.loan('NIC Asia')], 90000);
      expect(fresh.accounting.statements.balanceSheet(DateTime.now()).equity[Acc.drawings('Owner')], -1500);
    });

    test('door collection with a short handover and a delivery-invoiced order stay balanced', () async {
      final business = await TestBusiness.create();
      final owner = await business.device(UserRole.owner);
      final shop = owner.customers.createCustomer(name: 'Kirana', phone: '9866666666', location: 'Patan', creditLimit: 20000, openingBalance: 5000, by: owner.auth.currentUser!);
      final ghee = owner.inventory.createProduct(name: 'Ghee 5L', category: 'Oil', unitPrice: 5000, purchasePrice: 4000, stockQty: 10, reorderLevel: 1);
      final order = owner.ordering.placeOrderFor(shop, atMinimum({ghee: 1}), deliveryType: DeliveryType.delivery, staff: owner.auth.currentUser!)!;
      owner.ordering.assign(order, owner.ordering.deliverers.firstWhere((u) => u.role == UserRole.delivery), by: owner.auth.currentUser!);
      await pumpEventQueue();

      final delivery = await business.device(UserRole.delivery);
      final dOrder = delivery.ordering.orders.single;
      delivery.ordering.advanceOrderStatus(dOrder, OrderStatus.outForDelivery, userName: 'Delivery');
      await delivery.ordering.deliverAndCollect(dOrder, amount: 7000, method: PaymentMethod.cash, signature: testSignature(), signedName: 'x', collector: delivery.auth.currentUser!);
      await pumpEventQueue();
      final invoice = owner.sales.sales.firstWhere((x) => x.orderId == order.id);
      expect(owner.accounting.journal.any((e) => e.id == 'cogs-${invoice.id}'), isFalse, reason: 'delivery staff cannot see costs');

      final cashier = await business.cashier();
      expect(cashier.accounting.journal.any((e) => e.id == 'cogs-${invoice.id}'), isTrue, reason: 'a staff device books the cost on load');
      cashier.payments.settle(cashier.payments.pendingHandover.single, 6500, receiver: cashier.auth.currentUser!);
      await pumpEventQueue();

      final fresh = await business.device(UserRole.owner);
      expectBalanced(fresh);
      expect(fresh.accounting.statements.balances()[Acc.cashShortage], 500);
      expect(fresh.accounting.statements.balances()[Acc.cogs], 4000);
    });

    test('opening balances split capital by share and lock once trading starts', () async {
      final store = InMemoryRemoteStore();
      final auth = InMemoryAuthRepository();
      final scope = AppScope(store: store, authRepository: auth);
      expect(await signUp(scope, auth, phone: '9822222222', password: 'password123'), isTrue);
      final me = scope.auth.currentUser!;
      expect(scope.accounting.settings.owners.single.name, 'Owner', reason: 'set-up makes the owner the sole owner');
      expect(() => scope.accounting.saveSetup(owners: const [OwnerShare('A', 60), OwnerShare('B', 30)], by: me), throwsA(isA<AccountingException>()), reason: 'must total 100%');
      scope.accounting.saveSetup(owners: const [OwnerShare('A', 60), OwnerShare('B', 40)], by: me);
      expect(scope.accounting.openingLocked, isFalse);
      scope.accounting.postOpening(owns: {'cash': 150000, 'bank': 50000}, loans: {'Uncle': 20000}, date: DateTime.now(), by: me);
      final b = scope.accounting.statements.balances();
      expect(-b[Acc.capital('A')]!, 108000);
      expect(-b[Acc.capital('B')]!, 72000);
      expect(scope.cash.balanceOf('bank'), 50000);
      expect(scope.accounting.openingLocked, isTrue);
      expect(() => scope.accounting.postOpening(owns: {'cash': 1}, loans: const {}, date: DateTime.now(), by: me), throwsA(isA<AccountingException>()));
      expectBalanced(scope);
    });

    test('closing a fiscal year moves its profit to retained earnings and locks it', () async {
      final owner = await signedIn(UserRole.owner);
      final me = owner.auth.currentUser!;
      final lastYear = BsDate.fromAd(DateTime.now()).fiscalYear - 1;
      final (from, to) = BsDate.fiscalYearRange(lastYear);
      final inYear = from.add(const Duration(days: 10));
      expect(() => owner.accounting.manualEntry({Acc.receivables: 1000, Acc.sales: -900}, 'x', inYear, by: me), throwsA(isA<AccountingException>()), reason: 'unbalanced');
      expect(() => owner.accounting.manualEntry({'cash': 1000, Acc.sales: -1000}, 'x', inYear, by: me), throwsA(isA<AccountingException>()), reason: 'money moves only for real');
      owner.accounting.manualEntry({Acc.receivables: 1000, Acc.sales: -1000}, 'Old invoice', inYear, by: me);
      final end = DateTime(to.year, to.month, to.day, 23, 59, 59);
      owner.accounting.closeYear(end, by: me);

      final b = owner.accounting.statements.balances(to: end);
      expect(b[Acc.sales] ?? 0, 0);
      expect(b[Acc.retained], -1000);
      expect(owner.accounting.statements.profitAndLoss(from, end).profit, 1000, reason: 'closing entries are left out of profit');
      expect(() => owner.accounting.manualEntry({Acc.receivables: 1, Acc.sales: -1}, 'late', inYear, by: me), throwsA(isA<AccountingException>()));
      expect(owner.settings.current.closedThrough, end);
      owner.settings.setSafeguard(Safeguard.signature, false);
      expect(owner.settings.current.closedThrough, end, reason: 'saving other settings keeps the close date');
    });

    test('accountant export has the statements, journal and VAT books', () async {
      final owner = await signedIn(UserRole.owner);
      owner.settings.setVat(registered: true, pan: '601234567', rate: 13, pricesIncludeVat: true);
      final p = owner.inventory.products.first;
      await owner.sales.sell(items: [SaleItem(product: p, qty: 1, unitPrice: p.unitPrice)], isCredit: false, userName: 'Owner');
      final period = standardPeriods().last;
      final csv = accountantCsv(owner, period);
      for (final section in ['PROFIT AND LOSS', 'BALANCE SHEET', 'TRIAL BALANCE', 'JOURNAL', 'SALES BOOK', 'PURCHASE BOOK']) {
        expect(csv, contains(section));
      }
      expect(csv, contains('601234567'));
      expect((await accountantPdf(owner, period)).length, greaterThan(1000));
    });

    test('BS calendar: known new-year and fiscal-year dates', () {
      expect(BsDate.fromAd(DateTime(2024, 4, 13)), const BsDate(2081, 1, 1));
      expect(BsDate.fromAd(DateTime(2025, 4, 14)), const BsDate(2082, 1, 1));
      expect(const BsDate(2082, 4, 1).toAd(), DateTime(2025, 7, 17));
      expect(BsDate.fromAd(DateTime(2025, 7, 16)).fiscalYear, 2081);
      expect(BsDate.fromAd(DateTime(2025, 7, 17)).fiscalYear, 2082);
      expect(BsDate.fiscalYearLabel(2082), '2082/83');
    });
  });

  group('VAT', () {
    Future<AppScope> vatShop({bool included = true}) async {
      final owner = await signedIn(UserRole.owner);
      owner.settings.setVat(registered: true, pan: '601234567', rate: 13, pricesIncludeVat: included);
      return owner;
    }

    test('VAT-inclusive tax invoices: numbered in order, VAT split out, exempt goods left out, books balanced', () async {
      final owner = await vatShop();
      final me = owner.auth.currentUser!;
      final rice = owner.inventory.createProduct(name: 'Rice', category: 'General', unitPrice: 113, purchasePrice: 80, stockQty: 100, reorderLevel: 1);
      final salt = owner.inventory.createProduct(name: 'Salt', category: 'General', unitPrice: 50, purchasePrice: 30, stockQty: 100, reorderLevel: 1, vatExempt: true);
      expect(() => owner.sales.recordSale(items: [SaleItem(product: rice, qty: 1, unitPrice: 113)], isCredit: false, userName: me.name), throwsStateError,
          reason: 'a VAT shop never records an unnumbered sale');

      final first = await owner.sales.sell(items: [SaleItem(product: rice, qty: 2, unitPrice: 113), SaleItem(product: salt, qty: 1, unitPrice: 50)], isCredit: false, userName: me.name);
      final second = await owner.sales.sell(items: [SaleItem(product: rice, qty: 1, unitPrice: 113)], isCredit: false, userName: me.name);
      final fy = BsDate.fiscalYearLabel(BsDate.fromAd(DateTime.now()).fiscalYear);
      expect(first.invoiceNumber, '$fy-0001');
      expect(second.invoiceNumber, '$fy-0002');
      expect(first.total, 276);
      expect(first.vatAmount, 26);
      expect(first.exemptAmount, 50);
      expect(first.taxableAmount, 200);

      await owner.sales.reverse(first, SaleStatus.returned, 'damaged', userName: me.name);
      final note = owner.sales.creditNoteFor(first)!;
      expect(note.number, 'CN $fy-0001');
      expect(first.status, SaleStatus.returned);
      expect(await owner.sales.reverse(first, SaleStatus.returned, 'again', userName: me.name), isFalse);

      final (from, to) = (DateTime.now().subtract(const Duration(days: 1)), DateTime.now().add(const Duration(days: 1)));
      final book = salesBook(owner.sales, from, to);
      expect(book.map((r) => r.vat), [26, 13, -26]);
      final b = owner.accounting.statements.balances();
      expect(-b[Acc.vatPayable]!, 13, reason: 'only the kept sale\'s VAT is owed');
      for (final c in owner.accounting.checks) {
        expect(c.books, closeTo(c.records, 0.01), reason: c.label);
      }
    });

    test('VAT-exclusive prices: VAT is added on top', () async {
      final owner = await vatShop(included: false);
      final p = owner.inventory.createProduct(name: 'Oil', category: 'General', unitPrice: 100, purchasePrice: 80, stockQty: 10, reorderLevel: 1);
      final sale = await owner.sales.sell(items: [SaleItem(product: p, qty: 1, unitPrice: 100)], isCredit: true, customer: owner.customers.customers.first, userName: 'Owner');
      expect(sale.vatAmount, 13);
      expect(sale.total, 113);
      expect(sale.netSales, 100);
    });

    test('purchases record the supplier\'s VAT bill; paying the VAT return offsets it', () async {
      final owner = await vatShop();
      final me = owner.auth.currentUser!;
      final rice = owner.inventory.createProduct(name: 'Rice', category: 'General', unitPrice: 1130, purchasePrice: 800, stockQty: 0, reorderLevel: 1);
      owner.purchasing.createPurchase(
        supplier: owner.suppliers.suppliers.first,
        items: [PurchaseItem(product: rice, qty: 10, unitCost: 800)],
        paidAmount: 9040,
        userName: me.name,
        vatAmount: 1040,
        supplierBillNo: 'RT-1',
        supplierBillDate: DateTime.now(),
      );
      expect(rice.purchasePrice, 800, reason: 'cost excludes the claimable VAT');
      await owner.sales.sell(items: [SaleItem(product: rice, qty: 10, unitPrice: 1130)], isCredit: false, userName: me.name);
      final (from, to) = (DateTime.now().subtract(const Duration(days: 1)), DateTime.now().add(const Duration(days: 1)));
      expect(purchaseBook(owner.purchasing, from, to).single.vat, 1040);
      owner.cash.vatPaid(1300, 1040, 'cash', 'this month', userName: me.name);
      final b = owner.accounting.statements.balances();
      expect(b[Acc.vatPayable] ?? 0, 0);
      expect(b[Acc.vatInput] ?? 0, 0);
      for (final c in owner.accounting.checks) {
        expect(c.books, closeTo(c.records, 0.01), reason: c.label);
      }
    });

    test('delivering an order in a VAT shop issues a numbered tax invoice', () async {
      final business = await TestBusiness.create(safeguards: false);
      final owner = await business.device(UserRole.owner);
      owner.settings.setVat(registered: true, pan: '601234567', rate: 13, pricesIncludeVat: true);
      final shop = owner.customers.customers.first;
      final ghee = owner.inventory.createProduct(name: 'Ghee', category: 'Oil', unitPrice: 1130, purchasePrice: 900, stockQty: 5, reorderLevel: 1);
      final order = owner.ordering.placeOrderFor(shop, atMinimum({ghee: 1}), deliveryType: DeliveryType.delivery, staff: owner.auth.currentUser!)!;
      expect(order.vatAmount, 130);
      owner.ordering.assign(order, owner.ordering.deliverers.firstWhere((u) => u.role == UserRole.delivery), by: owner.auth.currentUser!);
      await pumpEventQueue();
      final delivery = await business.device(UserRole.delivery);
      final dOrder = delivery.ordering.orders.single;
      expect(() => delivery.ordering.advanceOrderStatus(dOrder, OrderStatus.delivered, userName: 'Delivery'), throwsStateError);
      await delivery.ordering.deliverAndCollect(dOrder, amount: 0, method: PaymentMethod.cash, collector: delivery.auth.currentUser!);
      await pumpEventQueue();
      final invoice = owner.sales.sales.firstWhere((s) => s.orderId == order.id);
      expect(invoice.invoiceNumber, endsWith('-0001'));
      expect(invoice.vatAmount, 130);
      expect(invoice.buyerPan, shop.pan);
    });
  });

  group('co-owners', () {
    test('the founder adds a co-owner with owner rights, except erasing the shop', () async {
      final business = await TestBusiness.create();
      final founder = await business.device(UserRole.owner);
      final staff = await business.device(UserRole.employee);
      expect((await staff.employees.createEmployeeAccount(name: 'X', email: testEmail('9811'), phone: '9811', password: 'password123', role: UserRole.owner, userName: 'E')).error,
          contains('founding owner'));
      expect(founder.auth.isFounder, isTrue);
      final added = await founder.employees.createEmployeeAccount(
          name: 'Sita', email: testEmail('9812'), phone: '9812', password: 'password123', role: UserRole.owner, userName: 'Owner', byFounder: founder.auth.isFounder);
      expect(added.error, isNull);
      founder.accounting.saveSetup(owners: const [OwnerShare('Owner', 60), OwnerShare('Sita', 40)], by: founder.auth.currentUser!);
      await pumpEventQueue();

      final sita = AppScope(store: business.store, authRepository: business.auth.forDevice());
      expect(await sita.auth.login(testEmail('9812'), 'password123'), isTrue, reason: sita.auth.loginError);
      expect(sita.auth.currentUser!.role, UserRole.owner);
      expect(sita.auth.isFounder, isFalse);
      sita.cash.capitalIn('Sita', 80000, 'cash', userName: 'Sita');
      await pumpEventQueue();
      await expectLater(sita.settings.resetBusiness(owner: sita.auth.currentUser!, typedName: 'Test Shop', password: 'password123'),
          throwsA(isA<AuthException>().having((e) => e.message, 'message', contains('founding owner'))));

      // Sita has capital booked: she can't be dropped from the owners until it is paid out.
      expect(() => founder.accounting.saveSetup(owners: const [OwnerShare('Owner', 100)], by: founder.auth.currentUser!), throwsA(isA<AccountingException>()));
    });

    test('a founder with co-owners must hand over before deleting their account; the shop carries on', () async {
      final business = await TestBusiness.create();
      final founder = await business.device(UserRole.owner);
      await founder.employees.createEmployeeAccount(
          name: 'Sita', email: testEmail('9812'), phone: '9812', password: 'password123', role: UserRole.owner, userName: 'Owner', byFounder: true);
      await pumpEventQueue();
      await expectLater(founder.auth.deleteAccount(password: TestBusiness.password, typedShopName: 'Test Shop'),
          throwsA(isA<AuthException>().having((e) => e.message, 'message', contains('Hand the founding owner role'))));

      final sitaProfile = founder.employees.employees.firstWhere((u) => u.name == 'Sita');
      founder.employees.handOverFounding(sitaProfile, by: founder.auth.currentUser!);
      await pumpEventQueue();
      final again = await business.device(UserRole.owner);
      expect(again.auth.isFounder, isFalse);
      expect(await again.auth.ownedShopNames(), isEmpty, reason: 'deleting now only leaves the shop');
      await again.auth.deleteAccount(password: TestBusiness.password);

      final sita = AppScope(store: business.store, authRepository: business.auth.forDevice());
      expect(await sita.auth.login(testEmail('9812'), 'password123'), isTrue);
      expect(sita.auth.isFounder, isTrue);
      expect(sita.inventory.products, isNotEmpty, reason: 'the shop was not wiped');
      expect(sita.employees.employees.any((u) => u.name == kFormerStaffName), isTrue);
    });

    test('a co-owner can leave; only the founder lets them back', () async {
      final business = await TestBusiness.create();
      final founder = await business.device(UserRole.owner);
      await founder.employees.createEmployeeAccount(
          name: 'Sita', email: testEmail('9812'), phone: '9812', password: 'password123', role: UserRole.owner, userName: 'Owner', byFounder: true);
      await pumpEventQueue();
      final sita = AppScope(store: business.store, authRepository: business.auth.forDevice());
      await sita.auth.login(testEmail('9812'), 'password123');
      await sita.auth.leaveShop();
      await pumpEventQueue();
      final retry = AppScope(store: business.store, authRepository: business.auth.forDevice());
      expect(await retry.auth.login(testEmail('9812'), 'password123'), isFalse);
      expect(retry.auth.loginError, contains('deactivated'));
      expect(() => founder.auth.leaveShop(), throwsA(isA<AuthException>()), reason: 'the founder hands over instead');
    });
  });

  group('permissions', () {
    test('owner has full permissions, employee cannot manage products or view accounting', () async {
      final business = await TestBusiness.create();
      final scope = await business.device(UserRole.owner);
      expect(scope.auth.can(Permission.manageProducts), isTrue);
      expect(scope.auth.can(Permission.viewAccounting), isTrue);

      await scope.auth.logout();
      expect(await scope.auth.login(testEmail(TestBusiness.phones[UserRole.employee]!), TestBusiness.password), isTrue);
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

    test('"Can handle cash & accounts" toggles the former accountant rights on a staff member', () async {
      final scope = await signedIn(UserRole.owner);
      final staff = scope.employees.employees.firstWhere((u) => u.phone == TestBusiness.phones[UserRole.employee]);
      expect(staff.can(Permission.reconcileCash), isFalse);

      scope.employees.setCashAccess(staff, true, userName: 'Owner');
      expect(staff.permissions.containsAll({...defaultRolePermissions[UserRole.employee]!, ...cashPermissions}), isTrue);

      scope.employees.setCashAccess(staff, false, userName: 'Owner');
      expect(staff.permissions, defaultRolePermissions[UserRole.employee]);
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

      deviceA.sales.recordSale(items: [SaleItem(product: productA, qty: 2, unitPrice: productA.unitPrice)], isCredit: false, userName: 'Owner');
      deviceB.sales.recordSale(items: [SaleItem(product: productB, qty: 3, unitPrice: productB.unitPrice)], isCredit: false, userName: 'Employee');
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
      await device.auth.login(testEmail(TestBusiness.phones[UserRole.owner]!), TestBusiness.password);
      recording.commits.clear();

      final product = device.inventory.products.first;
      final customer = device.customers.customers.first;
      device.sales.recordSale(items: [SaleItem(product: product, qty: 1, unitPrice: product.unitPrice)], isCredit: true, customer: customer, userName: 'Owner');
      await pumpEventQueue();

      expect(recording.commits, hasLength(1), reason: 'sale + stock + balance + audit must land all-or-nothing');
      expect(recording.commits.single.map((op) => op.collection).toSet(),
          containsAll([for (final c in ['sales', 'products', 'customers', 'auditLog']) 'shops/${business.shopId}/$c']));
      expect(owner.sales.sales, hasLength(1));
    });
  });

  group('accounts', () {
    test('sign-up: email verified before the shop; an abandoned sign-up resumes after login', () async {
      final store = InMemoryRemoteStore();
      final auth = InMemoryAuthRepository();
      final scope = AppScope(store: store, authRepository: auth);
      await expectLater(scope.auth.signUp('not-an-email', 'password123'), throwsA(isA<AuthException>()));
      await expectLater(scope.auth.signUp('Me@Shop.test', 'short'), throwsA(isA<AuthException>()));
      expect(auth.currentAccountId, isNull);
      await scope.auth.signUp(' Me@Shop.test ', 'password123');
      await expectLater(scope.auth.confirmEmailVerified(), throwsA(isA<AuthException>()), reason: 'link not opened yet');
      expect(await scope.auth.setUpBusiness(businessName: 'Shop', ownerName: 'Me', phone: '9822222222', includeSampleData: false), isFalse);
      expect(scope.auth.loginError, contains('Verify your email'));

      // Left before verifying: logging in brings back the remaining steps.
      final later = AppScope(store: store, authRepository: auth.forDevice());
      expect(await later.auth.login('me@shop.test', 'password123'), isFalse);
      expect(later.auth.needsSetup, isTrue);
      expect(later.auth.loginError, isNull);
      await expectLater(later.auth.signUp('me@shop.test', 'password999'), throwsA(isA<AuthException>()), reason: 'email taken');
      auth.verifyEmail('me@shop.test');
      await later.auth.confirmEmailVerified();
      expect(await later.auth.setUpBusiness(businessName: 'Shop', ownerName: 'Me', phone: '9822222222', includeSampleData: false), isTrue, reason: later.auth.loginError);
      expect(later.auth.currentUser!.role, UserRole.owner);
      expect(later.auth.currentUser!.email, 'me@shop.test');
      expect(later.auth.needsSetup, isFalse);
    });

    test('Account → Set up another shop: same login gets a second shop; staff logins verify their email first', () async {
      final a = await TestBusiness.create();
      final owner = await a.device(UserRole.owner);
      expect(await owner.auth.setUpBusiness(businessName: 'Shop 2', ownerName: 'Owner', phone: TestBusiness.phones[UserRole.owner]!, includeSampleData: false), isTrue);
      expect(owner.settings.current.businessName, 'Shop 2');
      expect(owner.auth.shops, hasLength(2));

      // A staff login (created by the owner) never verified its email.
      final staffPhone = TestBusiness.phones[UserRole.employee]!;
      final staff = await a.device(UserRole.employee);
      expect(await staff.auth.setUpBusiness(businessName: 'Staff Shop', ownerName: 'E', phone: staffPhone, includeSampleData: false), isFalse);
      expect(staff.auth.loginError, contains('Verify your email'));
      final again = await a.device(UserRole.employee);
      a.auth.verifyEmail(testEmail(staffPhone));
      await again.auth.confirmEmailVerified();
      expect(await again.auth.setUpBusiness(businessName: 'Staff Shop', ownerName: 'E', phone: staffPhone, includeSampleData: false), isTrue, reason: again.auth.loginError);
      expect(again.auth.currentUser!.role, UserRole.owner);
    });

    test('two shops on one backend: separate data, staff stay in their shop, reset of one leaves the other', () async {
      final a = await TestBusiness.create();
      final aOwner = await a.device(UserRole.owner);
      // A second owner sets up shop B on the same backend and accounts.
      final bOwner = AppScope(store: a.store, authRepository: a.auth.forDevice());
      expect(await signUp(bOwner, a.auth, phone: '9811111111', password: 'password123', shop: 'Shop B', owner: 'B'), isTrue,
          reason: bOwner.auth.loginError);
      final bShop = (await a.store.get('accounts', bOwner.auth.currentUser!.id))!['shopIds'].single as String;
      expect(bShop, isNot(a.shopId));
      expect((await bOwner.employees.createEmployeeAccount(name: 'B staff', email: testEmail('9811111112'), phone: '9811111112', password: 'password123', role: UserRole.employee, userName: 'B')).error, isNull);

      final bProduct = bOwner.inventory.createProduct(name: 'Only in B', category: 'Misc', unitPrice: 10, purchasePrice: 5, stockQty: 3, reorderLevel: 0);
      aOwner.sales.recordSale(items: [SaleItem(product: aOwner.inventory.products.first, qty: 1, unitPrice: 1)], isCredit: false, userName: 'Owner', allowBelowMinimum: true);
      await pumpEventQueue();

      expect(bOwner.inventory.products.map((p) => p.id), [bProduct.id]);
      expect(bOwner.customers.customers, isEmpty);
      expect(bOwner.sales.sales, isEmpty);
      expect(bOwner.employees.employees.map((u) => u.name), unorderedEquals(['B', 'B staff']));
      expect(bOwner.settings.current.businessName, 'Shop B');
      expect(aOwner.inventory.products.where((p) => p.id == bProduct.id), isEmpty);
      expect(aOwner.employees.employees.map((u) => u.name), isNot(contains('B staff')));
      expect(aOwner.settings.current.businessName, 'Test Shop');

      final bStaff = AppScope(store: a.store, authRepository: a.auth.forDevice());
      expect(await bStaff.auth.login(testEmail('9811111112'), 'password123'), isTrue);
      expect(bStaff.inventory.products.map((p) => p.id), [bProduct.id], reason: 'staff land in their own shop');
      final aStaff = await a.device(UserRole.employee);
      expect(aStaff.inventory.products.where((p) => p.id == bProduct.id), isEmpty);

      final bDocs = a.store.documentCount('shops/$bShop/');
      await aOwner.settings.resetBusiness(owner: aOwner.auth.currentUser!, typedName: 'Test Shop', password: TestBusiness.password);
      expect(a.store.documentCount('shops/${a.shopId}/'), 0);
      expect(await a.store.get('shops', a.shopId), isNull);
      expect(await a.store.get('shops', bShop), isNotNull);
      expect(a.store.documentCount('shops/$bShop/'), bDocs, reason: 'shop B untouched');
      final bAgain = AppScope(store: a.store, authRepository: a.auth.forDevice());
      expect(await bAgain.auth.login(testEmail('9811111111'), 'password123'), isTrue);
      expect(bAgain.inventory.products.map((p) => p.id), [bProduct.id]);
    });

    test('a login already staff in shop A is added to shop B, picks a shop at login, and switches', () async {
      final a = await TestBusiness.create();
      final employeePhone = TestBusiness.phones[UserRole.employee]!;
      await a.device(UserRole.employee); // signing in once registers the phone
      final bOwner = AppScope(store: a.store, authRepository: a.auth.forDevice());
      expect(await signUp(bOwner, a.auth, phone: '9811111111', password: 'password123', shop: 'Shop B', owner: 'B'), isTrue);
      final bProduct = bOwner.inventory.createProduct(name: 'Only in B', category: 'Misc', unitPrice: 10, purchasePrice: 5, stockQty: 3, reorderLevel: 0);

      final added = await bOwner.employees.createEmployeeAccount(name: 'Shared', email: testEmail(employeePhone), phone: employeePhone, password: '', role: UserRole.delivery, userName: 'B');
      expect(added, (error: null, existingLogin: true));
      final unused = await bOwner.employees.createEmployeeAccount(name: 'C', email: testEmail(TestBusiness.cashierPhone), phone: TestBusiness.cashierPhone, password: 'password123', role: UserRole.employee, userName: 'B');
      expect(unused.error, contains('sign in once'), reason: 'a login that never signed in cannot be found');
      await pumpEventQueue();

      final shared = AppScope(store: a.store, authRepository: a.auth.forDevice());
      expect(await shared.auth.login(testEmail(employeePhone), TestBusiness.password), isFalse, reason: 'picker first');
      expect(shared.auth.loginError, isNull);
      expect(shared.auth.shops.map((s) => s.name), ['Test Shop', 'Shop B']);
      final bShop = shared.auth.shops.last.id;

      await shared.auth.pickShop(bShop);
      expect(shared.auth.currentUser?.role, UserRole.delivery, reason: 'role is per shop');
      expect(shared.inventory.products.map((p) => p.id), [bProduct.id]);
      expect(shared.customers.customers, isEmpty);

      shared.auth.switchShop();
      expect(shared.auth.currentUser, isNull);
      expect(shared.inventory.products, isEmpty);
      await shared.auth.pickShop(a.shopId);
      expect(shared.auth.currentUser?.role, UserRole.employee);
      expect(shared.inventory.products.map((p) => p.id), isNot(contains(bProduct.id)));
      expect(shared.customers.customers, isNotEmpty);
      expect((await a.store.get('accounts', shared.auth.currentUser!.id))!['shopIds'], [a.shopId, bShop]);

      // One shop: straight in, no picker.
      final single = await a.device(UserRole.delivery);
      expect(single.auth.shops, hasLength(1));
    });

    test('a deactivated employee cannot log in; wrong passwords are rejected', () async {
      final business = await TestBusiness.create();
      final owner = await business.device(UserRole.owner);
      final employee = owner.employees.employees.firstWhere((u) => u.role == UserRole.employee);
      owner.employees.setActive(employee, false, userName: 'Owner');
      await pumpEventQueue();

      final other = AppScope(store: business.store, authRepository: business.auth);
      expect(await other.auth.login(testEmail(TestBusiness.phones[UserRole.employee]!), TestBusiness.password), isFalse);
      expect(other.auth.loginError, contains('deactivated'));
      expect(await other.auth.login(testEmail(TestBusiness.phones[UserRole.owner]!), 'wrong'), isFalse);
    });

    test('employee accounts: duplicate email, bad email and short password refused, session unchanged', () async {
      final owner = await signedIn(UserRole.owner);
      expect((await owner.employees.createEmployeeAccount(name: 'Dup', email: testEmail(TestBusiness.phones[UserRole.employee]!), phone: TestBusiness.phones[UserRole.employee]!, password: 'password123', role: UserRole.employee, userName: 'Owner')).error, isNotNull);
      expect((await owner.employees.createEmployeeAccount(name: 'Bad', email: 'nope', phone: '9822222223', password: 'password123', role: UserRole.employee, userName: 'Owner')).error, contains('valid email'));
      expect((await owner.employees.createEmployeeAccount(name: 'Short', email: testEmail('9822222222'), phone: '9822222222', password: 'short', role: UserRole.employee, userName: 'Owner')).error, contains('8 characters'));
      expect(owner.auth.currentUser?.role, UserRole.owner, reason: 'creating an account must not switch the session');
    });

    test('change password, then reset by email', () async {
      final business = await TestBusiness.create();
      final email = testEmail(TestBusiness.phones[UserRole.employee]!);
      final device = await business.device(UserRole.employee);

      await device.auth.changePassword(TestBusiness.password, 'newpassword1');
      expect(() => device.auth.changePassword('wrong-current', 'another123'), throwsA(isA<AuthException>()));
      await device.auth.logout();

      await expectLater(device.auth.sendPasswordReset('nonsense'), throwsA(isA<AuthException>()));
      await device.auth.sendPasswordReset(' ${email.toUpperCase()} ');
      expect(business.auth.sentResets, [email]);
      business.auth.resetPasswordFor(email, 'reset12345');
      expect(await device.auth.login(email, 'reset12345'), isTrue);
    });
  });

  paymentTests();

  test('More features: all off by default, toggles sync to other devices, saving details keeps them', () async {
    final business = await TestBusiness.create();
    final owner = await business.device(UserRole.owner);
    final staff = await business.device(UserRole.employee);
    expect(Feature.values.where(owner.settings.has), isEmpty);

    owner.settings.setFeature(Feature.suppliers, true);
    owner.settings.setFeature(Feature.expiry, true);
    owner.settings.setFeature(Feature.expiry, false);
    await pumpEventQueue();
    expect(Feature.values.where(staff.settings.has), [Feature.suppliers]);

    final s = owner.settings.current;
    owner.settings.update(businessName: 'Renamed', businessAddress: s.businessAddress, businessPhone: s.businessPhone, defaultLowStockThreshold: 3, taxPercent: 0);
    await pumpEventQueue();
    expect(staff.settings.current.businessName, 'Renamed');
    expect(Feature.values.where(staff.settings.has), [Feature.suppliers]);
  });

  test('shop settings: currency/country code default at sign-up; invoices and amounts use the shop name and currency', () async {
    final business = await TestBusiness.create();
    final owner = await business.device(UserRole.owner);
    expect(owner.settings.current.currency, 'NPR');
    expect(owner.settings.current.countryCode, '+977');
    expect(owner.sales.businessName, 'Test Shop');
    expect(formatNpr(250000), 'NPR 2,50,000');

    final s = owner.settings.current;
    owner.settings.update(businessName: 'Renamed', businessAddress: s.businessAddress, businessPhone: s.businessPhone, defaultLowStockThreshold: 3, taxPercent: 0, currency: 'Rs.');
    await pumpEventQueue();
    final staff = await business.device(UserRole.employee);
    expect(staff.sales.businessName, 'Renamed');
    expect(staff.settings.current.currency, 'Rs.');
    expect(formatNpr(-1500), '-Rs. 1,500');
    currencyLabel = 'NPR';
  });

  group('business reset', () {
    test('owner reset erases everything; setup starts fresh with the same login', () async {
      final business = await TestBusiness.create();
      final owner = await business.device(UserRole.owner);
      final product = owner.inventory.products.first;
      owner.sales.recordSale(items: [SaleItem(product: product, qty: 1, unitPrice: product.unitPrice)], isCredit: false, userName: 'Owner');
      await pumpEventQueue();
      expect(business.store.documentCount('shops'), greaterThan(20));

      final ownerUser = owner.auth.currentUser!;
      await expectLater(owner.settings.resetBusiness(owner: ownerUser, typedName: 'Wrong Shop', password: TestBusiness.password), throwsA(isA<AuthException>()));
      await expectLater(owner.settings.resetBusiness(owner: ownerUser, typedName: 'Test Shop', password: 'wrong-password'), throwsA(isA<AuthException>()));
      final cashier = await business.cashier();
      await expectLater(cashier.settings.resetBusiness(owner: cashier.auth.currentUser!, typedName: 'Test Shop', password: TestBusiness.password), throwsA(isA<AuthException>()));

      business.store.online = false;
      await expectLater(owner.settings.resetBusiness(owner: ownerUser, typedName: 'Test Shop', password: TestBusiness.password),
          throwsA(isA<AuthException>().having((e) => e.message, 'message', contains('No internet'))));
      expect(business.store.documentCount('shops'), greaterThan(20), reason: 'nothing deleted offline');
      business.store.online = true;

      await owner.settings.resetBusiness(owner: ownerUser, typedName: 'Test Shop', password: TestBusiness.password);
      await owner.auth.logout();
      expect(business.store.documentCount('shops'), 0);
      expect((await business.store.get('accounts', ownerUser.id))!['shopIds'], isEmpty);

      final fresh = AppScope(store: business.store, authRepository: business.auth);
      expect(await fresh.auth.login(testEmail(TestBusiness.phones[UserRole.employee]!), TestBusiness.password), isFalse, reason: 'old staff profiles are gone');
      // The owner's login has no shop left: logging in resumes sign-up.
      expect(await fresh.auth.login(testEmail(TestBusiness.phones[UserRole.owner]!), TestBusiness.password), isFalse);
      expect(fresh.auth.needsSetup, isTrue);
      expect(
        await signUp(fresh, business.auth, phone: TestBusiness.phones[UserRole.owner]!, password: TestBusiness.password, shop: 'New Shop'),
        isTrue,
        reason: fresh.auth.loginError,
      );
      expect(fresh.inventory.products, isEmpty);
      expect(fresh.settings.current.businessName, 'New Shop');
    });
  });

  group('account deletion', () {
    test('staff deletion anonymises their profile; their sales stay and still resolve; the login is gone', () async {
      final business = await TestBusiness.create();
      final employee = await business.device(UserRole.employee);
      final me = employee.auth.currentUser!;
      final product = employee.inventory.products.first;
      employee.sales.recordSale(items: [SaleItem(product: product, qty: 1, unitPrice: product.unitPrice)], isCredit: false, userName: me.name, userId: me.id);
      await pumpEventQueue();
      final phone = TestBusiness.phones[UserRole.employee]!;
      expect(await business.store.get('emails', testEmail(phone)), isNotNull);

      expect(await employee.auth.ownedShopNames(), isEmpty);
      await expectLater(employee.auth.deleteAccount(password: 'wrong-password'), throwsA(isA<AuthException>()));
      business.store.online = false;
      await expectLater(employee.auth.deleteAccount(password: TestBusiness.password),
          throwsA(isA<AuthException>().having((e) => e.message, 'message', contains('No internet'))));
      business.store.online = true;
      expect(employee.auth.currentUser, isNotNull);

      await employee.auth.deleteAccount(password: TestBusiness.password);
      expect(employee.auth.currentUser, isNull);
      expect(employee.auth.loginNotice, contains('deleted'));
      expect(await business.store.get('emails', testEmail(phone)), isNull);
      expect(await business.store.get('accounts', me.id), isNull);
      final profile = (await business.store.get('shops/${business.shopId}/users', me.id))!;
      expect(profile, containsPair('name', kFormerStaffName));
      expect(profile, containsPair('phone', ''));
      expect(profile, containsPair('email', ''));
      expect(profile, containsPair('active', false));

      final owner = await business.device(UserRole.owner);
      final sale = owner.sales.sales.lastWhere((s) => s.createdByUserId == me.id);
      expect(owner.auth.userRepository.byId(sale.createdByUserId!)?.name, kFormerStaffName);
      final again = AppScope(store: business.store, authRepository: business.auth.forDevice());
      expect(await again.auth.login(testEmail(phone), TestBusiness.password), isFalse);
      // The phone is free for a new login.
      expect((await owner.employees.createEmployeeAccount(name: 'New', email: testEmail(phone), phone: phone, password: 'password456', role: UserRole.employee, userName: 'Owner')).error, isNull);
    });

    test('owner deletion wipes their shop, anonymises them where they are staff, and leaves the other shop intact', () async {
      final a = await TestBusiness.create();
      final aOwner = await a.device(UserRole.owner); // signed in, so B can add this login as staff
      final me = aOwner.auth.currentUser!;
      final bOwner = AppScope(store: a.store, authRepository: a.auth.forDevice());
      expect(await signUp(bOwner, a.auth, phone: '9811111111', password: 'password123', shop: 'Shop B', owner: 'B'), isTrue);
      final bShop = bOwner.auth.shops.single.id;
      expect((await bOwner.employees.createEmployeeAccount(name: 'A owner', email: testEmail(me.phone), phone: me.phone, password: '', role: UserRole.employee, userName: 'B')).existingLogin, isTrue);
      await pumpEventQueue();
      final bDocs = a.store.documentCount('shops/$bShop/');

      final csv = shopExportCsv(aOwner);
      expect(csv, contains('CUSTOMERS'));
      expect(csv, contains(aOwner.customers.customers.first.name));

      expect(await aOwner.auth.ownedShopNames(), ['Test Shop']);
      await expectLater(aOwner.auth.deleteAccount(password: TestBusiness.password, typedShopName: 'Shop B'), throwsA(isA<AuthException>()));
      await aOwner.auth.deleteAccount(password: TestBusiness.password, typedShopName: 'Test Shop');

      expect(aOwner.auth.currentUser, isNull);
      expect(a.store.documentCount('shops/${a.shopId}/'), 0);
      expect(await a.store.get('shops', a.shopId), isNull);
      expect(await a.store.get('accounts', me.id), isNull);
      expect(await a.store.get('phones', me.phone), isNull);
      expect(a.store.documentCount('shops/$bShop/'), bDocs, reason: 'shop B keeps every doc');
      expect((await a.store.get('shops/$bShop/users', me.id))!['name'], kFormerStaffName);
      final b = AppScope(store: a.store, authRepository: a.auth.forDevice());
      expect(await b.auth.login(testEmail('9811111111'), 'password123'), isTrue);
      expect(b.settings.current.businessName, 'Shop B');
      final deleted = AppScope(store: a.store, authRepository: a.auth.forDevice());
      expect(await deleted.auth.login(testEmail(me.phone), TestBusiness.password), isFalse, reason: 'deleted login');
      final staffOfA = AppScope(store: a.store, authRepository: a.auth.forDevice());
      expect(await staffOfA.auth.login(testEmail(TestBusiness.phones[UserRole.employee]!), TestBusiness.password), isFalse);
    });
  });

  group('customers and confirmation', () {
    test('sales staff can add a customer, but only with no credit', () async {
      final business = await TestBusiness.create();
      final employee = await business.device(UserRole.employee);
      final c = employee.customers.createCustomer(name: 'Walk-in Traders', phone: '9877', location: 'Kalanki', creditLimit: 50000, openingBalance: 9000, by: employee.auth.currentUser!);
      expect(c.creditLimit, 0);
      expect(c.outstandingBalance, 0);
      await pumpEventQueue();
      final owner = await business.device(UserRole.owner);
      expect(owner.notificationRepository.notificationsFor(owner.auth.currentUser!).any((n) => n.title.contains('Walk-in Traders')), isTrue);
      final delivery = await business.device(UserRole.delivery);
      expect(() => delivery.customers.createCustomer(name: 'x', phone: '1', location: '', by: delivery.auth.currentUser!), throwsStateError);
    });

    test('phone order → delivery needs a signature, and the payment counts as confirmed', () async {
      final business = await TestBusiness.create();
      final employee = await business.device(UserRole.employee);
      final shop = employee.customers.customers.firstWhere((c) => c.name == 'Thapa Trading');
      final product = employee.inventory.products.first;
      final order = employee.ordering.placeOrderFor(shop, atMinimum({product: 2}), deliveryType: DeliveryType.delivery, address: 'Balkumari', staff: employee.auth.currentUser!)!;
      expect(order.placedByStaffName, employee.auth.currentUser!.name);
      await pumpEventQueue();

      final owner = await business.device(UserRole.owner);
      final o = owner.ordering.orders.single;
      owner.ordering.assign(o, owner.ordering.deliverers.firstWhere((u) => u.role == UserRole.delivery), by: owner.auth.currentUser!);
      for (final st in [OrderStatus.confirmed, OrderStatus.preparing, OrderStatus.ready, OrderStatus.outForDelivery]) {
        owner.ordering.advanceOrderStatus(o, st, userName: 'Owner');
      }
      await pumpEventQueue();

      final delivery = await business.device(UserRole.delivery);
      final d = delivery.ordering.orders.single;
      final me = delivery.auth.currentUser!;
      await expectLater(delivery.ordering.deliverAndCollect(d, amount: 1000, method: PaymentMethod.cash, collector: me),
          throwsA(isA<PaymentException>().having((e) => e.message, 'message', contains('sign'))));
      final payment = await delivery.ordering.deliverAndCollect(d, amount: 1000, method: PaymentMethod.cash, signature: testSignature(), signedName: 'Ram Thapa', collector: me);
      await pumpEventQueue();

      expect(payment!.confirmedBySignature, isTrue);
      expect(payment.isCustomerConfirmed, isTrue);
      expect(d.receivedBy, 'Ram Thapa');
      expect(Signature.decode(d.receivedSignature)!.strokes.single, hasLength(3));
      expect(owner.payments.unconfirmed, isEmpty);
    });

    test('unsigned payment: owner/cash staff confirms by phone, never the collector', () async {
      final business = await TestBusiness.create();
      final employee = await business.device(UserRole.employee);
      final cashier = await business.cashier();
      final shop = employee.customers.customers.firstWhere((c) => c.name == 'Thapa Trading');
      final p1 = employee.payments.record(shop, 800, method: PaymentMethod.cash, collector: employee.auth.currentUser!);
      employee.payments.record(shop, 900, method: PaymentMethod.cash, collector: employee.auth.currentUser!);
      await pumpEventQueue();

      expect(() => employee.payments.confirmByPhone(p1, staff: employee.auth.currentUser!), throwsA(isA<PaymentException>()));
      final mine = cashier.payments.unconfirmed;
      expect(mine, hasLength(2));
      cashier.payments.confirmByPhone(mine.first, staff: cashier.auth.currentUser!);
      cashier.payments.disputeOnBehalf(mine.last, 'Says he paid 90', staff: cashier.auth.currentUser!);
      await pumpEventQueue();

      expect(cashier.payments.unconfirmed, isEmpty);
      expect(cashier.payments.disputed.single.disputedByName, contains('phone call'));
      expect(mine.first.phoneConfirmedByName, cashier.auth.currentUser!.name);
    });

    test('receipts and statements render as PDF', () async {
      final business = await TestBusiness.create();
      final cashier = await business.cashier();
      final shop = cashier.customers.customers.first;
      final payment = cashier.payments.record(shop, 1500, method: PaymentMethod.cash, signature: testSignature(), signedName: 'Hari', collector: cashier.auth.currentUser!);
      final receipt = await paymentReceiptPdf(payment, businessName: 'Test Shop');
      final statement = await statementPdf(shop, cashier.payments.statementFor(shop), businessName: 'Test Shop');
      expect(String.fromCharCodes(receipt.take(5)), '%PDF-');
      expect(String.fromCharCodes(statement.take(5)), '%PDF-');
    });
  });

  group('customer management', () {
    test('add and edit a customer; credit limit changes are audited', () async {
      final owner = await signedIn(UserRole.owner);
      final customer = owner.customers.createCustomer(name: 'New Shop', phone: '9855555555', location: 'Patan', creditLimit: 10000, by: owner.auth.currentUser!);
      owner.customers.updateCustomer(customer, name: 'New Shop Pvt', phone: customer.phone, location: 'Patan', creditLimit: 15000, userName: 'Owner');
      await pumpEventQueue();

      expect(owner.customers.customers.firstWhere((c) => c.id == customer.id).creditLimit, 15000);
      expect(owner.auditRepository.entries.any((e) => e.action == 'Credit limit changed' && e.entityId == customer.id), isTrue);
    });
  });
}


void paymentTests() {
  /// Customer owes 5,000 (limit 20,000), orders exactly 5,000, and the
  /// delivery person is assigned. Returns the devices and the order.
  Future<({TestBusiness business, AppScope owner, AppScope cashier, AppScope delivery, CustomerOrder order})> scenario({bool safeguards = true}) async {
    final business = await TestBusiness.create(safeguards: safeguards);
    final owner = await business.device(UserRole.owner);
    final shop = owner.customers.createCustomer(name: 'Kathmandu Kirana', phone: '9866666666', location: 'Patan', creditLimit: 20000, openingBalance: 5000, by: owner.auth.currentUser!);
    final ghee = owner.inventory.createProduct(name: 'Ghee 5L', category: 'Oil', unitPrice: 5000, stockQty: 10, reorderLevel: 1);
    final order = owner.ordering.placeOrderFor(shop, atMinimum({ghee: 1}), deliveryType: DeliveryType.delivery, address: 'Patan', staff: owner.auth.currentUser!)!;
    final deliveryUser = owner.ordering.deliverers.firstWhere((u) => u.role == UserRole.delivery);
    owner.ordering.assign(order, deliveryUser, by: owner.auth.currentUser!);
    for (final status in [OrderStatus.confirmed, OrderStatus.preparing, OrderStatus.ready]) {
      owner.ordering.advanceOrderStatus(order, status, userName: 'Owner');
    }
    await pumpEventQueue();

    final delivery = await business.device(UserRole.delivery);
    final cashier = await business.cashier();
    return (business: business, owner: owner, cashier: cashier, delivery: delivery, order: order);
  }

  group('payment verification', () {
    test('customer pays 7,000 at the door on a 5,000 order: 5,000 settles the order, 2,000 the old balance', () async {
      final s = await scenario();
      final order = s.delivery.ordering.orders.single;
      s.delivery.ordering.advanceOrderStatus(order, OrderStatus.outForDelivery, userName: 'Delivery', userId: s.delivery.auth.currentUser!.id);
      final result = await s.delivery.ordering
          .deliverAndCollect(order, amount: 7000, method: PaymentMethod.cash, signature: testSignature(), signedName: 'Kirana owner', collector: s.delivery.auth.currentUser!);
      await pumpEventQueue();

      final payment = result!;
      expect(payment.appliedToOrder, 5000);
      expect(payment.appliedToPreviousBalance, 2000);
      expect(payment.balanceAfter, 3000);
      expect(payment.isCustomerConfirmed, isTrue);
      expect(payment.isPendingHandover, isTrue, reason: 'cash is with the delivery person until the shop counts it');

      final ownerCustomer = s.owner.customers.customers.firstWhere((c) => c.name == 'Kathmandu Kirana');
      expect(ownerCustomer.outstandingBalance, 3000);
      final statement = s.owner.payments.statementFor(ownerCustomer);
      expect(statement.balanced, isTrue);
      final invoice = s.owner.sales.sales.firstWhere((x) => x.orderId == order.id);
      expect(statement.dueFor(invoice), 0, reason: 'the order is fully paid');
      expect(statement.openingPaid, 2000);

      // Cash only reaches the books when someone else counts it in.
      final cashBefore = s.cashier.cash.cashInHand;
      final pending = s.cashier.payments.pendingHandover.single;
      s.cashier.payments.settle(pending, 7000, receiver: s.cashier.auth.currentUser!);
      await pumpEventQueue();
      expect(s.cashier.cash.cashInHand, cashBefore + 7000);
      expect(s.delivery.payments.payments.single.isSettled, isTrue);
    });

    test('short handover is recorded against the collector and flagged to the owner', () async {
      final s = await scenario();
      final order = s.delivery.ordering.orders.single;
      s.delivery.ordering.advanceOrderStatus(order, OrderStatus.outForDelivery, userName: 'Delivery');
      await s.delivery.ordering.deliverAndCollect(order, amount: 7000, method: PaymentMethod.cash, signature: testSignature(), signedName: 'x', collector: s.delivery.auth.currentUser!);
      await pumpEventQueue();

      s.cashier.payments.settle(s.cashier.payments.pendingHandover.single, 6500, receiver: s.cashier.auth.currentUser!);
      await pumpEventQueue();

      expect(s.owner.payments.shortfalls.single.shortfall, 500);
      expect(s.owner.notificationRepository.notificationsFor(s.owner.auth.currentUser!).any((n) => n.title == 'Cash missing'), isTrue);
      expect(s.owner.customers.customers.firstWhere((c) => c.name == 'Kathmandu Kirana').outstandingBalance, 3000, reason: 'the customer paid in full; the gap is not theirs');
    });

    test('nobody receives their own collection; the delivery role cannot receive at all', () async {
      final s = await scenario();
      final order = s.delivery.ordering.orders.single;
      s.delivery.ordering.advanceOrderStatus(order, OrderStatus.outForDelivery, userName: 'Delivery');
      await s.delivery.ordering.deliverAndCollect(order, amount: 1000, method: PaymentMethod.cash, signature: testSignature(), signedName: 'x', collector: s.delivery.auth.currentUser!);
      final payment = s.delivery.payments.payments.single;
      expect(() => s.delivery.payments.settle(payment, 1000, receiver: s.delivery.auth.currentUser!), throwsA(isA<PaymentException>()));

      // An employee collects at the counter: waits for handover; cash staff's own counter collection settles at once.
      final employee = await s.business.device(UserRole.employee);
      final shop = employee.customers.customers.firstWhere((c) => c.name == 'Kathmandu Kirana');
      expect(employee.payments.record(shop, 500, method: PaymentMethod.cash, collector: employee.auth.currentUser!).isSettled, isFalse);
      final cashierShop = s.cashier.customers.customers.firstWhere((c) => c.name == 'Kathmandu Kirana');
      expect(s.cashier.payments.record(cashierShop, 500, method: PaymentMethod.cash, collector: s.cashier.auth.currentUser!).isSettled, isTrue);
      expect(() => s.cashier.payments.record(cashierShop, 500, method: PaymentMethod.wallet, collector: s.cashier.auth.currentUser!), throwsA(isA<PaymentException>()), reason: 'non-cash needs a reference');
    });

    test('delivered on credit, later paid at the counter: oldest balance is paid first', () async {
      final s = await scenario();
      final order = s.delivery.ordering.orders.single;
      s.delivery.ordering.advanceOrderStatus(order, OrderStatus.outForDelivery, userName: 'Delivery');
      final result = await s.delivery.ordering.deliverAndCollect(order, amount: 0, method: PaymentMethod.cash, signature: testSignature(), signedName: 'x', collector: s.delivery.auth.currentUser!);
      expect(result, isNull);
      await pumpEventQueue();

      final shop = s.cashier.customers.customers.firstWhere((c) => c.name == 'Kathmandu Kirana');
      expect(shop.outstandingBalance, 10000, reason: 'the invoice goes on the balance at delivery');
      s.cashier.payments.record(shop, 6000, method: PaymentMethod.bank, reference: 'NIC-1234', collector: s.cashier.auth.currentUser!);
      await pumpEventQueue();

      final statement = s.cashier.payments.statementFor(shop);
      final invoice = s.cashier.sales.sales.firstWhere((x) => x.orderId == order.id);
      expect(statement.openingPaid, 5000, reason: 'the old 5,000 is paid off first');
      expect(statement.dueFor(invoice), 4000);
      expect(shop.outstandingBalance, 4000);
      expect(statement.balanced, isTrue);
    });

    test('a disputed payment is reversed by the owner and the books still balance', () async {
      final s = await scenario();
      final employee = await s.business.device(UserRole.employee);
      final shop = employee.customers.customers.firstWhere((c) => c.name == 'Kathmandu Kirana');
      employee.payments.record(shop, 1000, method: PaymentMethod.cash, collector: employee.auth.currentUser!);
      employee.payments.record(shop, 2000, method: PaymentMethod.cash, collector: employee.auth.currentUser!);
      await pumpEventQueue();

      final cashier = s.cashier.auth.currentUser!;
      final recorded = s.cashier.payments.payments;
      s.cashier.payments.confirmByPhone(recorded[0], staff: cashier);
      s.cashier.payments.disputeOnBehalf(recorded[1], 'I paid 200, not 2,000', staff: cashier);
      expect(() => s.cashier.payments.confirmByPhone(recorded[1], staff: cashier), throwsA(isA<PaymentException>()));
      await pumpEventQueue();
      expect(s.owner.payments.disputed.single.disputeNote, contains('200'));

      final disputed = s.owner.payments.disputed.single;
      expect(() => s.cashier.payments.reverse(disputed, 'x', owner: s.cashier.auth.currentUser!), throwsA(isA<PaymentException>()), reason: 'owner only');
      s.owner.payments.reverse(disputed, 'Recorded wrong amount', owner: s.owner.auth.currentUser!);
      await pumpEventQueue();

      final ownerShop = s.owner.customers.customers.firstWhere((c) => c.name == 'Kathmandu Kirana');
      expect(ownerShop.outstandingBalance, 4000);
      expect(s.owner.payments.statementFor(ownerShop).balanced, isTrue);
      expect(s.owner.payments.statementFor(ownerShop).expectedBalance, 4000);
    });

    test('a balance changed outside sales and payments is detected', () async {
      final s = await scenario();
      final shop = s.owner.customers.customers.firstWhere((c) => c.name == 'Kathmandu Kirana');
      s.owner.customers.repository.applyBalanceChange(shop, -1500); // bypasses the payment flow
      final statement = s.owner.payments.statementFor(shop);
      expect(statement.balanced, isFalse);
      expect(statement.unexplainedDifference, -1500);
    });

    test('placing an order never checks credit; delivering past the limit is allowed, flagged and reported', () async {
      final s = await scenario();
      final me = s.owner.auth.currentUser!;
      final product = s.owner.inventory.products.firstWhere((p) => p.name == 'Ghee 5L');
      final shop = s.owner.customers.customers.firstWhere((c) => c.name == 'Kathmandu Kirana');
      // Owes 5,000 (limit 20,000); a 20,000 order is just an order.
      final big = s.owner.ordering.placeOrderFor(shop, atMinimum({product: 4}), deliveryType: DeliveryType.pickup, staff: me)!;
      expect(big.status, OrderStatus.placed);

      // Paying 6,000 at the door keeps them within the limit (5,000 + 20,000 − 6,000).
      await s.owner.ordering.deliverAndCollect(big, amount: 6000, method: PaymentMethod.cash, signature: testSignature(), signedName: 'x', collector: me);
      expect(s.owner.sales.sales.firstWhere((x) => x.orderId == big.id).flaggedForApproval, isFalse);
      await pumpEventQueue();

      // The other order on credit now takes them to 24,000: delivered anyway, flagged, owner told.
      final order = s.delivery.ordering.orders.single;
      s.delivery.ordering.advanceOrderStatus(order, OrderStatus.outForDelivery, userName: 'Delivery');
      await s.delivery.ordering.deliverAndCollect(order, amount: 0, method: PaymentMethod.cash, signature: testSignature(), signedName: 'x', collector: s.delivery.auth.currentUser!);
      await pumpEventQueue();
      expect(order.status, OrderStatus.delivered);
      expect(s.owner.sales.sales.firstWhere((x) => x.orderId == order.id).flaggedForApproval, isTrue);
      expect(s.owner.notificationRepository.notificationsFor(me).any((n) => n.title == 'Over credit limit'), isTrue);
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
        s.delivery.ordering.deliverAndCollect(order, amount: 7000, method: PaymentMethod.cash, signature: testSignature(), signedName: 'x', collector: s.delivery.auth.currentUser!),
        throwsA(isA<PaymentException>().having((e) => e.message, 'message', contains('No internet'))),
      );
      await pumpEventQueue();

      expect(order.status, OrderStatus.outForDelivery, reason: 'local copy rolled back');
      expect(shop.outstandingBalance, 5000);
      expect(order.items.single.product.stockQty, stock);
      expect(s.delivery.payments.payments, isEmpty);
      expect(s.owner.sales.sales.where((x) => x.orderId == order.id), isEmpty, reason: 'nothing reached the server');
    });

    test('reversing a payment already in the till refunds it out of the till', () async {
      final s = await scenario();
      final shop = s.cashier.customers.customers.firstWhere((c) => c.name == 'Kathmandu Kirana');
      final cashBefore = s.cashier.cash.cashInHand;
      s.cashier.payments.record(shop, 2000, method: PaymentMethod.cash, collector: s.cashier.auth.currentUser!);
      await pumpEventQueue();
      expect(s.cashier.cash.cashInHand, cashBefore + 2000);

      s.owner.payments.reverse(s.owner.payments.payments.single, 'Wrong customer', owner: s.owner.auth.currentUser!);
      await pumpEventQueue();
      expect(s.owner.cash.cashInHand, cashBefore, reason: 'refund entry takes it back out');
      final ownerShop = s.owner.customers.customers.firstWhere((c) => c.name == 'Kathmandu Kirana');
      expect(ownerShop.outstandingBalance, 5000);
      expect(s.owner.payments.statementFor(ownerShop).balanced, isTrue);
    });

    test('bank, wallet and cheque money lands in those accounts; deposits move cash to bank', () async {
      final s = await scenario();
      final shop = s.cashier.customers.customers.firstWhere((c) => c.name == 'Kathmandu Kirana');
      final a = s.cashier.auth.currentUser!;
      s.cashier.payments.record(shop, 1000, method: PaymentMethod.bank, reference: 'NIC-1', collector: a);
      s.cashier.payments.record(shop, 500, method: PaymentMethod.wallet, reference: 'ESEWA-9', collector: a);
      s.cashier.payments.record(shop, 300, method: PaymentMethod.cheque, reference: 'CHQ-7', collector: a);
      s.cashier.payments.record(shop, 800, method: PaymentMethod.cash, collector: a);
      s.cashier.cash.transfer('cash', 'bank', 600, '', userName: 'cashier');
      await pumpEventQueue();

      expect(s.cashier.cash.balanceOf('bank'), 1000 + 300 + 600);
      expect(s.cashier.cash.balanceOf('wallet'), 500);
      expect(s.cashier.cash.cashInHand, 800 - 600);
    });

    test('delivery staff never receive cost prices; audit entries carry the author', () async {
      final s = await scenario();
      final staffGhee = s.owner.inventory.products.firstWhere((p) => p.name == 'Basmati Rice 25kg');
      expect(staffGhee.purchasePrice, 2800);
      expect(s.delivery.inventory.products.firstWhere((p) => p.name == 'Basmati Rice 25kg').purchasePrice, 0);
      expect(s.owner.auditRepository.entries.first.userId, isNotNull);
    });

    test('safeguards start off and the owner turns them on for every device', () async {
      final s = await scenario(safeguards: false);
      expect(Safeguard.values.any(s.delivery.settings.guards), isFalse);
      s.owner.settings.enableAllSafeguards();
      await pumpEventQueue();
      expect(Safeguard.values.every(s.delivery.settings.guards), isTrue);
      expect(s.delivery.ordering.signatureRequired, isTrue);
    });

    test('safeguards off: unsigned, offline delivery settles at once as one batch; unsigned counter payments need no call', () async {
      final s = await scenario(safeguards: false);
      final recorded = <List<WriteOp>>[];
      s.business.store.rejectIf = (ops) {
        recorded.add(ops);
        return false;
      };
      final order = s.delivery.ordering.orders.single;
      s.delivery.ordering.advanceOrderStatus(order, OrderStatus.outForDelivery, userName: 'Delivery');
      await pumpEventQueue();
      recorded.clear();

      s.business.store.online = false; // queued like any write, not refused
      final payment = (await s.delivery.ordering.deliverAndCollect(order, amount: 7000, method: PaymentMethod.cash, collector: s.delivery.auth.currentUser!))!;
      await pumpEventQueue();
      expect(recorded, hasLength(1), reason: 'delivery + invoice + payment + settlement: one atomic batch');
      expect({for (final op in recorded.single) op.collection.split('/').last}, containsAll(['orders', 'sales', 'customerPayments', 'cashLedger']));
      expect(order.status, OrderStatus.delivered);
      expect(payment.confirmedBySignature, isFalse);
      expect(payment.isCustomerConfirmed, isTrue, reason: 'no phone check');
      expect(payment.isSettled && payment.settledAmount == 7000 && payment.settledById == s.delivery.auth.currentUser!.id, isTrue,
          reason: 'no handover: the collector counts it in at once');
      s.business.store.online = true;
      s.business.store.rejectIf = null;

      final cashBefore = s.owner.cash.cashInHand;
      final employee = await s.business.device(UserRole.employee);
      final shop = employee.customers.customers.firstWhere((c) => c.name == 'Kathmandu Kirana');
      final counter = employee.payments.record(shop, 500, method: PaymentMethod.cash, collector: employee.auth.currentUser!);
      await pumpEventQueue();
      expect(counter.isSettled, isTrue);
      expect(s.owner.cash.cashInHand, cashBefore + 500);
      expect(s.owner.payments.unconfirmed, isEmpty);
      expect(s.owner.payments.pendingHandover, isEmpty);
      expect(() => s.owner.payments.confirmByPhone(s.owner.payments.payments.last, staff: s.owner.auth.currentUser!), throwsA(isA<PaymentException>()));
    });

    test('each safeguard on its own', () async {
      final s = await scenario(safeguards: false);
      final employee = await s.business.device(UserRole.employee);
      final shop = employee.customers.customers.firstWhere((c) => c.name == 'Kathmandu Kirana');
      final me = employee.auth.currentUser!;

      s.owner.settings.setSafeguard(Safeguard.phoneConfirm, true);
      await pumpEventQueue();
      final unsigned = employee.payments.record(shop, 100, method: PaymentMethod.cash, collector: me);
      expect(unsigned.isCustomerConfirmed, isFalse, reason: 'waits for a phone check');
      expect(unsigned.isSettled, isTrue, reason: 'handover still off');

      s.owner.settings.setSafeguard(Safeguard.handover, true);
      await pumpEventQueue();
      final held = employee.payments.record(shop, 100, method: PaymentMethod.cash, collector: me);
      expect(held.isPendingHandover, isTrue);
      expect(() => employee.payments.settle(held, 100, receiver: me), throwsA(isA<PaymentException>()));

      final order = s.delivery.ordering.orders.single;
      s.delivery.ordering.advanceOrderStatus(order, OrderStatus.outForDelivery, userName: 'Delivery');
      s.owner.settings.setSafeguard(Safeguard.signature, true);
      s.owner.settings.setSafeguard(Safeguard.onlineOnly, true);
      await pumpEventQueue();
      await expectLater(s.delivery.ordering.deliverAndCollect(order, amount: 0, method: PaymentMethod.cash, collector: s.delivery.auth.currentUser!),
          throwsA(isA<PaymentException>().having((e) => e.message, 'message', contains('sign'))));
      s.business.store.online = false;
      await expectLater(
          s.delivery.ordering.deliverAndCollect(order, amount: 0, method: PaymentMethod.cash, signature: testSignature(), signedName: 'x', collector: s.delivery.auth.currentUser!),
          throwsA(isA<PaymentException>().having((e) => e.message, 'message', contains('No internet'))));
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