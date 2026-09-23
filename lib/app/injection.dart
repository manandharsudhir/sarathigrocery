import 'package:sarathigrocery/app/sample_data.dart';
import 'package:sarathigrocery/core/data/remote_store.dart';
import 'package:sarathigrocery/core/data/write_queue.dart';
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
import 'package:sarathigrocery/features/sales/data/repositories/sale_repository_impl.dart';
import 'package:sarathigrocery/features/sales/presentation/controllers/sales_controller.dart';
import 'package:sarathigrocery/features/settings/data/repositories/settings_repository_impl.dart';
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
/// those two interfaces and passing them in.
class AppScope {
  factory AppScope({RemoteStore? store, AuthRepository? authRepository}) {
    final writes = WriteQueue(store ?? InMemoryRemoteStore());
    final authRepo = authRepository ?? InMemoryAuthRepository();

    final userRepository = UserRepositoryImpl();
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
      ])
        c.name: c..bind(writes),
    };

    Future<void> connect(AppUser user) async {
      await Future.wait([
        for (final entry in _loadPlan(user).entries) collections[entry.key]!.attach(id: entry.value.id, where: entry.value.where),
      ]);
      // One-off fixes for data written by older app versions.
      if (user.role == UserRole.owner) productRepository.migrateLegacyCosts();
    }

    void disconnect() {
      for (final c in collections.values) {
        c.detach();
      }
      orderRepository.clearCart(); // next login on this device shouldn't inherit it
    }

    // Owner "reset everything": deletes every document the backend holds.
    // The owner's profile + setup marker go last, in their own commit, so
    // the owner stays authorized for all earlier deletes. Online-only; a
    // failure part-way leaves the rest for a re-run.
    Future<void> wipeBackend(AppUser owner) async {
      final store = writes.store;
      final targets = <String, List<String>>{};
      for (final name in collections.keys) {
        if (name == 'meta' || name == 'deliveryCodes') continue;
        targets[name] = await store.listIds(name);
      }
      // Delivery codes are unreadable to the owner by design; delete by order id.
      targets['deliveryCodes'] = targets['orders'] ?? const [];
      for (final entry in targets.entries) {
        for (final id in entry.value) {
          if (entry.key == 'users' && id == owner.id) continue;
          writes.enqueue(DeleteOp(entry.key, id));
        }
      }
      await writes.flush(requireOnline: true);
      writes
        ..enqueue(DeleteOp('users', owner.id))
        ..enqueue(const DeleteOp('meta', 'setup'));
      await writes.flush(requireOnline: true);
    }

    final setUpBusiness = SetUpBusiness(
      userRepository,
      authRepo,
      settingsRepository,
      commit: writes.flush,
      writeSampleData: () => writeSampleData(writes),
    );

    final settlePayment = SettlePayment(paymentRepository, cashRepository, auditRepository, notificationRepository);
    final recordPayment = RecordPayment(customerRepository, paymentRepository, userRepository, auditRepository, notificationRepository, settlePayment);

    final payments = PaymentsController(
      paymentRepository,
      saleRepository,
      recordPayment,
      settlePayment,
      RespondToPayment(paymentRepository, auditRepository, notificationRepository),
      ReversePayment(customerRepository, paymentRepository, cashRepository, userRepository, auditRepository, notificationRepository),
    );

    return AppScope._(
      auth: AuthController(userRepository, authRepo, setUpBusiness, connect: connect, disconnect: disconnect),
      inventory: InventoryController(productRepository, auditRepository, notificationRepository),
      customers: CustomersController(customerRepository, auditRepository, userRepository, authRepo, payments),
      payments: payments,
      suppliers: SuppliersController(supplierRepository, auditRepository, cashRepository),
      sales: SalesController(saleRepository, productRepository, customerRepository, cashRepository, auditRepository, notificationRepository),
      purchasing: PurchasingController(purchaseRepository, productRepository, supplierRepository, cashRepository, auditRepository, notificationRepository),
      cash: CashController(cashRepository),
      ordering: OrderingController(orderRepository, productRepository, saleRepository, customerRepository, auditRepository, notificationRepository, userRepository, recordPayment, paymentRepository, writes.flush),
      employees: EmployeesController(userRepository, authRepo, auditRepository),
      settings: SettingsController(settingsRepository, authRepo, wipeBackend),
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
  /// - A customer sees the catalogue plus their own profile, account,
  ///   bills, payments, orders, delivery codes and notifications.
  static Map<String, ({String? id, Map<String, Object?> where})> _loadPlan(AppUser user) {
    const all = (id: null, where: <String, Object?>{});
    final own = (id: user.id, where: const <String, Object?>{});
    final mine = (id: null, where: <String, Object?>{'targetUserId': user.id});
    switch (user.role) {
      case UserRole.owner || UserRole.accountant || UserRole.employee:
        return {
          for (final name in [
            'users', 'products', 'productCosts', 'categories', 'stockAdjustments', 'customers', 'suppliers', 'cashLedger', 'expenses',
            'partnerLedger', 'sales', 'purchases', 'purchaseReturns', 'orders', 'notifications', 'settings', 'customerPayments',
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
      case UserRole.customer:
        final ofCustomer = (id: null, where: <String, Object?>{'customerId': user.linkedCustomerId ?? ''});
        return {
          'products': all,
          'categories': all,
          'settings': all,
          'users': own,
          'customers': (id: user.linkedCustomerId ?? '', where: const {}),
          'orders': ofCustomer,
          'sales': ofCustomer,
          'customerPayments': ofCustomer,
          'deliveryCodes': ofCustomer,
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
  final OrderingController ordering;
  final EmployeesController employees;
  final SettingsController settings;
  final AuditRepository auditRepository;
  final NotificationRepository notificationRepository;
}
