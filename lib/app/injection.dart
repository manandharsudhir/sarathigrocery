import 'package:sarathigrocery/app/sample_data.dart';
import 'package:sarathigrocery/core/data/remote_store.dart';
import 'package:sarathigrocery/core/data/write_queue.dart';
import 'package:sarathigrocery/features/accounting/data/repositories/journal_repository_impl.dart';
import 'package:sarathigrocery/features/accounting/domain/books.dart';
import 'package:sarathigrocery/features/accounting/domain/entities/accounts.dart';
import 'package:sarathigrocery/features/accounting/presentation/controllers/accounting_controller.dart';
import 'package:sarathigrocery/features/audit/data/repositories/audit_repository_impl.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/auth/data/repositories/user_repository_impl.dart';
import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/auth_repository.dart';
import 'package:sarathigrocery/features/auth/domain/usecases/set_up_business.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/cash/data/repositories/cash_repository_impl.dart';
import 'package:sarathigrocery/features/cash/presentation/controllers/cash_controller.dart';
import 'package:sarathigrocery/features/customers/data/repositories/customer_repository_impl.dart';
import 'package:sarathigrocery/features/customers/data/repositories/payment_repository_impl.dart';
import 'package:sarathigrocery/features/customers/domain/usecases/record_payment.dart';
import 'package:sarathigrocery/features/customers/domain/usecases/respond_to_payment.dart';
import 'package:sarathigrocery/features/customers/domain/usecases/reverse_payment.dart';
import 'package:sarathigrocery/features/customers/domain/usecases/settle_payment.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/payments_controller.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/customers_controller.dart';
import 'package:sarathigrocery/features/employees/presentation/controllers/employees_controller.dart';
import 'package:sarathigrocery/features/inventory/data/repositories/product_repository_impl.dart';
import 'package:sarathigrocery/features/inventory/presentation/controllers/inventory_controller.dart';
import 'package:sarathigrocery/features/notifications/data/repositories/notification_repository_impl.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';
import 'package:sarathigrocery/features/ordering/data/repositories/order_repository_impl.dart';
import 'package:sarathigrocery/features/ordering/presentation/controllers/ordering_controller.dart';
import 'package:sarathigrocery/features/purchasing/data/repositories/purchase_repository_impl.dart';
import 'package:sarathigrocery/features/purchasing/presentation/controllers/purchasing_controller.dart';
import 'package:sarathigrocery/features/sales/data/bill_numbers.dart';
import 'package:sarathigrocery/features/sales/data/repositories/sale_repository_impl.dart';
import 'package:sarathigrocery/features/sales/domain/entities/vat.dart';
import 'package:sarathigrocery/features/sales/presentation/controllers/sales_controller.dart';
import 'package:sarathigrocery/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:sarathigrocery/features/settings/domain/entities/business_settings.dart';
import 'package:sarathigrocery/features/settings/presentation/controllers/settings_controller.dart';
import 'package:sarathigrocery/features/suppliers/data/repositories/supplier_repository_impl.dart';
import 'package:sarathigrocery/features/suppliers/presentation/controllers/suppliers_controller.dart';

/// Composition root: constructs every repository and controller exactly
/// once and wires their dependencies. No DI framework — this is a plain
/// object graph built by hand.
///
/// The backend is chosen here and nowhere else: pass a [RemoteStore] +
/// [AuthRepository] pair (Firebase in `main.dart`; in-memory by default,
/// which is what tests use). Migrating to your own backend = implementing
/// those two interfaces and passing them in. Every shop's data lives under
/// `shops/{shopId}/`; [ShopScopedStore] adds that prefix, so nothing above
/// it knows about shops except login, setup and reset.
class AppScope {
  factory AppScope({RemoteStore? store, AuthRepository? authRepository}) {
    final backend = store ?? InMemoryRemoteStore();
    final shopStore = ShopScopedStore(backend);
    void useShop(String shopId) => shopStore.shopId = shopId;
    final writes = WriteQueue(shopStore);
    final authRepo = authRepository ?? InMemoryAuthRepository();

    final userRepository = UserRepositoryImpl(() => shopStore.shopId);
    final productRepository = ProductRepositoryImpl();
    final customerRepository = CustomerRepositoryImpl();
    final supplierRepository = SupplierRepositoryImpl();
    final cashRepository = CashRepositoryImpl();
    final saleRepository = SaleRepositoryImpl(productRepository, customerRepository);
    final purchaseRepository = PurchaseRepositoryImpl(productRepository, supplierRepository);
    final orderRepository = OrderRepositoryImpl(productRepository, customerRepository);
    final auditRepository = AuditRepositoryImpl(() => authRepo.currentAccountId);
    final notificationRepository = NotificationRepositoryImpl();
    final settingsRepository = SettingsRepositoryImpl();
    final paymentRepository = PaymentRepositoryImpl(customerRepository);
    final journalRepository = JournalRepositoryImpl();
    final billNumbers = BillNumbers(shopStore.get);
    final books = Books(journalRepository, () => settingsRepository.current);

    final collections = {
      for (final c in [
        ...userRepository.collections,
        ...productRepository.collections,
        ...customerRepository.collections,
        ...supplierRepository.collections,
        ...cashRepository.collections,
        ...saleRepository.collections,
        ...purchaseRepository.collections,
        ...orderRepository.collections,
        ...auditRepository.collections,
        ...notificationRepository.collections,
        ...settingsRepository.collections,
        ...paymentRepository.collections,
        ...journalRepository.collections,
        ...billNumbers.collections,
      ])
        c.name: c..bind(writes),
    };

    Future<void> connect(AppUser user) async {
      await Future.wait([
        for (final entry in _loadPlan(user).entries) collections[entry.key]!.attach(id: entry.value.id, where: entry.value.where),
      ]);
      // Delivery devices can't see costs: staff book the cost of what they invoiced.
      if (user.role != UserRole.delivery) books.postMissingCosts(saleRepository.sales);
    }

    void disconnect() {
      for (final c in collections.values) {
        c.detach();
      }
    }

    // Owner "reset" of [shopId] (and account deletion, for each shop the
    // owner owns): deletes that shop's subtree, never other shops.
    // The owner's profile, the shop doc and the owner's account entry go
    // last, in their own commit, so the owner stays authorized for all
    // earlier deletes (and the shop id stays taken until nothing is left
    // under it). Online-only; a failure part-way leaves the rest for a re-run.
    // Staff accounts keep a stale entry for the shop; login skips it.
    Future<void> wipeShop(String ownerId, String shopId) async {
      final current = shopStore.shopId;
      useShop(shopId);
      try {
        final targets = <String, List<String>>{};
        for (final name in collections.keys) {
          if (ShopScopedStore.global.contains(name)) continue;
          targets[name] = await shopStore.listIds(name);
        }
        for (final entry in targets.entries) {
          for (final id in entry.value) {
            if (entry.key == 'users' && id == ownerId) continue;
            writes.enqueue(DeleteOp(entry.key, id));
          }
        }
        await writes.flush(requireOnline: true);
        final ownerShops = await userRepository.shopIdsOf(ownerId);
        writes
          ..enqueue(DeleteOp('users', ownerId))
          ..enqueue(DeleteOp('shops', shopId));
        userRepository.setShopIds(ownerId, ownerShops..remove(shopId));
        await writes.flush(requireOnline: true);
      } finally {
        shopStore.shopId = current;
      }
    }

    Future<String> shopName(String shopId) async =>
        (await backend.get('shops/$shopId/settings', 'business'))?['businessName'] as String? ?? shopId;

    // This login's shops (stale entries skipped), read straight from the
    // backend because they span shops.
    // `owner` = founding owner (the only one whose leaving erases the shop).
    Future<List<({String id, bool owner})>> memberships(String uid) async => [
          for (final id in await userRepository.shopIdsOf(uid))
            if (await backend.get('shops/$id/users', uid) != null) (id: id, owner: (await backend.get('shops', id))?['ownerId'] == uid),
        ];

    // Account deletion: wipes every shop [me] founded, anonymises their
    // profile in the others (kept so records' user ids still resolve), then
    // deletes their emails/accounts docs. Online-only. The login itself is
    // deleted afterwards by AuthController. A founder with active co-owners
    // must hand the shop over first, so it isn't wiped under them.
    Future<void> deleteAccountData(AppUser me) async {
      final anonymise = <WriteOp>[];
      final mine = await memberships(me.id);
      for (final m in mine.where((m) => m.owner)) {
        for (final uid in await backend.listIds('shops/${m.id}/users')) {
          final p = await backend.get('shops/${m.id}/users', uid);
          if (uid != me.id && p?['role'] == UserRole.owner.name && p?['active'] == true) {
            throw AuthException('${await shopName(m.id)} has co-owners. Hand the founding owner role to one of them first (Employees).');
          }
        }
      }
      for (final m in mine) {
        if (m.owner) {
          await wipeShop(me.id, m.id);
        } else {
          anonymise.add(PutOp('shops/${m.id}/users', me.id, {'name': kFormerStaffName, 'phone': '', 'email': '', 'active': false}));
        }
      }
      await backend.commit([...anonymise, DeleteOp('emails', me.email), DeleteOp('accounts', me.id)], requireOnline: true);
    }


    final setUpBusiness = SetUpBusiness(
      userRepository,
      authRepo,
      settingsRepository,
      commit: writes.flush,
      writeSampleData: () => writeSampleData(writes, capital: books.capitalSplit),
      useShop: useShop,
    );

    bool guards(Safeguard g) => settingsRepository.current.guards(g);
    List<String> moneyAccounts() => moneyAccountIds(settingsRepository.current.moneyAccounts);
    VatTerms? vatTerms() {
      final s = settingsRepository.current;
      return s.vatRegistered ? (rate: s.taxPercent > 0 ? s.taxPercent : 13, included: s.pricesIncludeVat) : null;
    }
    final settlePayment = SettlePayment(paymentRepository, cashRepository, auditRepository, notificationRepository, guards, books);
    final recordPayment = RecordPayment(customerRepository, paymentRepository, auditRepository, notificationRepository, settlePayment, guards, books);

    final payments = PaymentsController(
      paymentRepository,
      saleRepository,
      recordPayment,
      settlePayment,
      RespondToPayment(paymentRepository, auditRepository, notificationRepository),
      ReversePayment(customerRepository, paymentRepository, cashRepository, auditRepository, books),
      () => settingsRepository.current.businessName,
    );

    // Filled in below; settings asks it who the founding owner is.
    late final AuthController auth;
    bool founder() => auth.isFounder;

    return AppScope._(
      auth: auth = AuthController(userRepository, authRepo, setUpBusiness, connect: connect, disconnect: disconnect, useShop: useShop, shopName: shopName,
          ownedShopNames: (uid) async => [for (final m in await memberships(uid)) if (m.owner) await shopName(m.id)],
          deleteAccountData: deleteAccountData, flush: writes.flush),
      inventory: InventoryController(productRepository, auditRepository, notificationRepository, books),
      customers: CustomersController(customerRepository, auditRepository, payments, notificationRepository, books),
      payments: payments,
      suppliers: SuppliersController(supplierRepository, auditRepository, cashRepository, books),
      sales: SalesController(saleRepository, productRepository, customerRepository, cashRepository, auditRepository, notificationRepository, () => settingsRepository.current.businessName, books, moneyAccounts: moneyAccounts, vat: vatTerms, billNumbers: billNumbers, commit: writes.flush, settings: () => settingsRepository.current),
      purchasing: PurchasingController(purchaseRepository, productRepository, supplierRepository, cashRepository, auditRepository, notificationRepository, books, moneyAccounts: moneyAccounts, vatShop: () => settingsRepository.current.vatRegistered, margin: () => settingsRepository.current.marginPercent),
      cash: CashController(cashRepository, books, auditRepository, () => settingsRepository.current),
      accounting: AccountingController(books, cashRepository, customerRepository, supplierRepository, productRepository, paymentRepository, saleRepository, settingsRepository, auditRepository),
      ordering: OrderingController(orderRepository, productRepository, saleRepository, customerRepository, auditRepository, notificationRepository, userRepository, recordPayment, paymentRepository, writes.flush, () => settingsRepository.current.businessName, guards, books, vat: vatTerms, billNumbers: billNumbers),
      employees: EmployeesController(userRepository, authRepo, auditRepository),
      settings: SettingsController(settingsRepository, authRepo, (owner) => wipeShop(owner.id, shopStore.shopId!), isFounder: () => founder()),
      auditRepository: auditRepository,
      notificationRepository: notificationRepository,
    );
  }

  /// Which collections [user] mirrors, and how narrowly. Must stay in step
  /// with `firestore.rules` (mirrored by the "app load plan" test in
  /// `firestore_tests/`): a watch the rules reject fails that login.
  /// - Staff see the whole business (audit log: owner only).
  /// - Delivery staff see the catalogue, customers (address, balance), and
  ///   only the orders assigned to them and payments they collected.
  static Map<String, ({String? id, Map<String, Object?> where})> _loadPlan(AppUser user) {
    const all = (id: null, where: <String, Object?>{});
    final own = (id: user.id, where: const <String, Object?>{});
    final mine = (id: null, where: <String, Object?>{'targetUserId': user.id});
    switch (user.role) {
      case UserRole.owner || UserRole.employee:
        return {
          for (final name in [
            'users', 'products', 'productCosts', 'categories', 'stockAdjustments', 'customers', 'suppliers', 'cashLedger', 'expenses',
            'journal', 'creditNotes', 'sales', 'purchases', 'purchaseReturns', 'orders', 'notifications', 'settings', 'customerPayments',
            if (user.role == UserRole.owner) 'auditLog',
          ])
            name: all,
        };
      case UserRole.delivery:
        return {
          'products': all,
          'categories': all,
          'settings': all,
          'customers': all,
          'users': own,
          'orders': (id: null, where: {'assignedToId': user.id}),
          'customerPayments': (id: null, where: {'collectedById': user.id}),
          'notifications': mine,
        };
    }
  }

  AppScope._({
    required this.auth,
    required this.inventory,
    required this.customers,
    required this.payments,
    required this.suppliers,
    required this.sales,
    required this.purchasing,
    required this.cash,
    required this.accounting,
    required this.ordering,
    required this.employees,
    required this.settings,
    required this.auditRepository,
    required this.notificationRepository,
  });

  final AuthController auth;
  final InventoryController inventory;
  final CustomersController customers;
  final PaymentsController payments;
  final SuppliersController suppliers;
  final SalesController sales;
  final PurchasingController purchasing;
  final CashController cash;
  final AccountingController accounting;
  final OrderingController ordering;
  final EmployeesController employees;
  final SettingsController settings;
  final AuditRepository auditRepository;
  final NotificationRepository notificationRepository;
}
