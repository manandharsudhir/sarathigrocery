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
    final auditRepository = AuditRepositoryImpl();
    final notificationRepository = NotificationRepositoryImpl();
    final settingsRepository = SettingsRepositoryImpl();

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
      ])
        c.name: c..bind(writes),
    };

    Future<void> connect(AppUser user) => Future.wait([
          for (final entry in _loadPlan(user).entries)
            collections[entry.key]!.attach(id: entry.value.id, where: entry.value.where),
        ]);

    void disconnect() {
      for (final c in collections.values) {
        c.detach();
      }
      orderRepository.clearCart(); // next login on this device shouldn't inherit it
    }

    final setUpBusiness = SetUpBusiness(
      userRepository,
      authRepo,
      settingsRepository,
      commit: writes.flush,
      writeSampleData: () => writeSampleData(writes),
    );

    return AppScope._(
      auth: AuthController(userRepository, authRepo, setUpBusiness, connect: connect, disconnect: disconnect),
      inventory: InventoryController(productRepository, auditRepository, notificationRepository),
      customers: CustomersController(customerRepository, auditRepository, cashRepository, notificationRepository, userRepository, authRepo),
      suppliers: SuppliersController(supplierRepository, auditRepository, cashRepository),
      sales: SalesController(saleRepository, productRepository, customerRepository, cashRepository, auditRepository, notificationRepository),
      purchasing: PurchasingController(purchaseRepository, productRepository, supplierRepository, cashRepository, auditRepository, notificationRepository),
      cash: CashController(cashRepository),
      ordering: OrderingController(orderRepository, productRepository, auditRepository, notificationRepository, userRepository),
      employees: EmployeesController(userRepository, authRepo, auditRepository),
      settings: SettingsController(settingsRepository),
      auditRepository: auditRepository,
      notificationRepository: notificationRepository,
    );
  }

  /// Which collections [user] mirrors, and how narrowly. Must stay in step
  /// with `firestore.rules`: a watch the rules reject fails the login.
  /// Staff see the whole business; a customer sees the catalogue plus
  /// their own profile, account, orders and notifications — nothing else.
  static Map<String, ({String? id, Map<String, Object?> where})> _loadPlan(AppUser user) {
    const all = (id: null, where: <String, Object?>{});
    if (user.role != UserRole.customer) {
      return {
        for (final name in [
          'users', 'products', 'categories', 'stockAdjustments', 'customers', 'suppliers', 'cashLedger', 'expenses',
          'partnerLedger', 'sales', 'purchases', 'purchaseReturns', 'orders', 'notifications', 'settings',
          if (user.role == UserRole.owner) 'auditLog',
        ])
          name: all,
      };
    }
    final customerId = user.linkedCustomerId ?? '';
    return {
      'products': all,
      'categories': all,
      'settings': all,
      'users': (id: user.id, where: const {}),
      'customers': (id: customerId, where: const {}),
      'orders': (id: null, where: {'customerId': customerId}),
      'notifications': (id: null, where: {'targetUserId': user.id}),
    };
  }

  AppScope._({
    required this.auth,
    required this.inventory,
    required this.customers,
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
