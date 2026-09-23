import 'package:flutter/material.dart';

import 'package:sarathigrocery/app/injection.dart';
import 'package:sarathigrocery/core/services/app_signal.dart';
import 'package:sarathigrocery/app/widgets/more_menu_screen.dart';
import 'package:sarathigrocery/app/widgets/quick_action_fab.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/auth/presentation/pages/account_security_dialogs.dart';
import 'package:sarathigrocery/features/auth/presentation/pages/profile_screen.dart';
import 'package:sarathigrocery/features/cash/presentation/pages/cash_screen.dart';
import 'package:sarathigrocery/features/customers/presentation/pages/customers_screen.dart';
import 'package:sarathigrocery/features/customers/presentation/pages/my_collections_screen.dart';
import 'package:sarathigrocery/features/customers/presentation/pages/payments_screen.dart';
import 'package:sarathigrocery/features/dashboard/presentation/dashboard_nav.dart';
import 'package:sarathigrocery/features/dashboard/presentation/pages/accountant_dashboard.dart';
import 'package:sarathigrocery/features/dashboard/presentation/pages/customer_dashboard.dart';
import 'package:sarathigrocery/features/dashboard/presentation/pages/employee_dashboard.dart';
import 'package:sarathigrocery/features/dashboard/presentation/pages/owner_dashboard.dart';
import 'package:sarathigrocery/features/employees/presentation/pages/employees_screen.dart';
import 'package:sarathigrocery/features/inventory/presentation/pages/categories_screen.dart';
import 'package:sarathigrocery/features/inventory/presentation/pages/inventory_screen.dart';
import 'package:sarathigrocery/features/ordering/presentation/pages/cart_screen.dart';
import 'package:sarathigrocery/features/ordering/presentation/pages/customer_orders_screen.dart';
import 'package:sarathigrocery/features/ordering/presentation/pages/deliveries_screen.dart';
import 'package:sarathigrocery/features/ordering/presentation/pages/products_browse_screen.dart';
import 'package:sarathigrocery/features/ordering/presentation/pages/staff_orders_screen.dart';
import 'package:sarathigrocery/features/purchasing/presentation/pages/purchases_screen.dart';
import 'package:sarathigrocery/features/reports/presentation/pages/reports_screen.dart';
import 'package:sarathigrocery/features/sales/presentation/pages/sales_history_screen.dart';
import 'package:sarathigrocery/features/settings/presentation/pages/business_settings_screen.dart';
import 'package:sarathigrocery/features/suppliers/presentation/pages/suppliers_screen.dart';
import 'package:sarathigrocery/features/audit/presentation/pages/audit_log_screen.dart';

class _RoleNav {
  const _RoleNav({required this.destinations, required this.screens, this.fabOnFirstTab = false});

  final List<NavigationDestination> destinations;
  final List<Widget> screens;
  final bool fabOnFirstTab;
}

_RoleNav _navFor(UserRole role, AppScope scope, void Function(int) goToTab) {
  switch (role) {
    case UserRole.owner:
      return _RoleNav(
        fabOnFirstTab: true,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Inventory'),
          NavigationDestination(icon: Icon(Icons.list_alt_outlined), selectedIcon: Icon(Icons.list_alt), label: 'Orders'),
          NavigationDestination(icon: Icon(Icons.point_of_sale_outlined), selectedIcon: Icon(Icons.point_of_sale), label: 'Sales'),
          NavigationDestination(icon: Icon(Icons.more_horiz), selectedIcon: Icon(Icons.more_horiz), label: 'More'),
        ],
        screens: [
          OwnerDashboard(
            sales: scope.sales,
            cash: scope.cash,
            customers: scope.customers,
            suppliers: scope.suppliers,
            ordering: scope.ordering,
            inventory: scope.inventory,
            auth: scope.auth,
            notifications: scope.notificationRepository,
            nav: DashboardNav(
              openInventory: () => goToTab(1),
              openOrders: () => goToTab(2),
              openSales: () => goToTab(3),
            ),
          ),
          InventoryScreen(controller: scope.inventory, auth: scope.auth),
          StaffOrdersScreen(controller: scope.ordering, auth: scope.auth),
          SalesHistoryScreen(sales: scope.sales, inventory: scope.inventory, customers: scope.customers, auth: scope.auth),
          MoreMenuScreen(items: _ownerMoreItems(scope)),
        ],
      );
    case UserRole.accountant:
      return _RoleNav(
        fabOnFirstTab: true,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.point_of_sale_outlined), selectedIcon: Icon(Icons.point_of_sale), label: 'Sales'),
          NavigationDestination(icon: Icon(Icons.list_alt_outlined), selectedIcon: Icon(Icons.list_alt), label: 'Orders'),
          NavigationDestination(icon: Icon(Icons.payments_outlined), selectedIcon: Icon(Icons.payments), label: 'Payments'),
          NavigationDestination(icon: Icon(Icons.more_horiz), selectedIcon: Icon(Icons.more_horiz), label: 'More'),
        ],
        screens: [
          AccountantDashboard(
            sales: scope.sales,
            cash: scope.cash,
            customers: scope.customers,
            suppliers: scope.suppliers,
            auth: scope.auth,
            notifications: scope.notificationRepository,
            nav: DashboardNav(
              openSales: () => goToTab(1),
              openOrders: () => goToTab(2),
            ),
          ),
          SalesHistoryScreen(sales: scope.sales, inventory: scope.inventory, customers: scope.customers, auth: scope.auth),
          StaffOrdersScreen(controller: scope.ordering, auth: scope.auth),
          CashScreen(controller: scope.cash),
          MoreMenuScreen(items: _accountantMoreItems(scope)),
        ],
      );
    case UserRole.employee:
      return _RoleNav(
        fabOnFirstTab: true,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.list_alt_outlined), selectedIcon: Icon(Icons.list_alt), label: 'Orders'),
          NavigationDestination(icon: Icon(Icons.point_of_sale_outlined), selectedIcon: Icon(Icons.point_of_sale), label: 'Sales'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Stock'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Customers'),
        ],
        screens: [
          EmployeeDashboard(
            sales: scope.sales,
            ordering: scope.ordering,
            inventory: scope.inventory,
            customers: scope.customers,
            auth: scope.auth,
            notifications: scope.notificationRepository,
            nav: DashboardNav(
              openOrders: () => goToTab(1),
              openSales: () => goToTab(2),
              openInventory: () => goToTab(3),
              openCustomers: () => goToTab(4),
            ),
          ),
          StaffOrdersScreen(controller: scope.ordering, auth: scope.auth),
          SalesHistoryScreen(sales: scope.sales, inventory: scope.inventory, customers: scope.customers, auth: scope.auth),
          InventoryScreen(controller: scope.inventory, auth: scope.auth),
          CustomersScreen(controller: scope.customers, auth: scope.auth),
        ],
      );
    case UserRole.delivery:
      return _RoleNav(
        destinations: const [
          NavigationDestination(icon: Icon(Icons.local_shipping_outlined), selectedIcon: Icon(Icons.local_shipping), label: 'Deliveries'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'Collections'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Account'),
        ],
        screens: [
          DeliveriesScreen(ordering: scope.ordering, auth: scope.auth),
          MyCollectionsScreen(payments: scope.payments, auth: scope.auth),
          ProfileScreen(auth: scope.auth),
        ],
      );
    case UserRole.customer:
      final cartCount = scope.ordering.cart.fold<int>(0, (sum, i) => sum + i.qty);
      return _RoleNav(
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          const NavigationDestination(icon: Icon(Icons.shopping_bag_outlined), selectedIcon: Icon(Icons.shopping_bag), label: 'Products'),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: cartCount > 0,
              label: Text('$cartCount'),
              child: const Icon(Icons.shopping_cart_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: cartCount > 0,
              label: Text('$cartCount'),
              child: const Icon(Icons.shopping_cart),
            ),
            label: 'Cart',
          ),
          const NavigationDestination(icon: Icon(Icons.list_alt_outlined), selectedIcon: Icon(Icons.list_alt), label: 'Orders'),
          const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Account'),
        ],
        screens: [
          CustomerDashboard(
            auth: scope.auth,
            customers: scope.customers,
            ordering: scope.ordering,
            notifications: scope.notificationRepository,
            nav: DashboardNav(
              openProducts: () => goToTab(1),
              openCart: () => goToTab(2),
              openOrders: () => goToTab(3),
            ),
          ),
          ProductsBrowseScreen(inventory: scope.inventory, ordering: scope.ordering, onOpenCart: () => goToTab(2)),
          CartScreen(ordering: scope.ordering, customers: scope.customers, auth: scope.auth),
          CustomerOrdersScreen(controller: scope.ordering, auth: scope.auth),
          ProfileScreen(auth: scope.auth),
        ],
      );
  }
}

List<MoreMenuItem> _ownerMoreItems(AppScope scope) => [
      MoreMenuItem(icon: Icons.price_check_outlined, label: 'Customer Payments', builder: (_) => PaymentsScreen(payments: scope.payments, auth: scope.auth)),
      MoreMenuItem(icon: Icons.local_shipping_outlined, label: 'Purchases', builder: (_) => PurchasesScreen(purchasing: scope.purchasing, suppliers: scope.suppliers, inventory: scope.inventory, auth: scope.auth)),
      MoreMenuItem(icon: Icons.people_outline, label: 'Customers', builder: (_) => CustomersScreen(controller: scope.customers, auth: scope.auth)),
      MoreMenuItem(icon: Icons.factory_outlined, label: 'Suppliers', builder: (_) => SuppliersScreen(controller: scope.suppliers, purchasing: scope.purchasing, cash: scope.cash, auth: scope.auth)),
      MoreMenuItem(icon: Icons.payments_outlined, label: 'Payments', builder: (_) => CashScreen(controller: scope.cash)),
      MoreMenuItem(icon: Icons.receipt_long_outlined, label: 'Expenses', builder: (_) => CashScreen(controller: scope.cash, initialTabIndex: 1)),
      MoreMenuItem(icon: Icons.account_balance_outlined, label: 'Accounting', builder: (_) => CashScreen(controller: scope.cash, initialTabIndex: 2)),
      MoreMenuItem(icon: Icons.category_outlined, label: 'Categories', builder: (_) => CategoriesScreen(controller: scope.inventory)),
      MoreMenuItem(icon: Icons.bar_chart_outlined, label: 'Reports', builder: (_) => ReportsScreen(sales: scope.sales, purchasing: scope.purchasing, cash: scope.cash, inventory: scope.inventory, customers: scope.customers, suppliers: scope.suppliers)),
      MoreMenuItem(icon: Icons.badge_outlined, label: 'Employees', builder: (_) => EmployeesScreen(controller: scope.employees, auth: scope.auth)),
      MoreMenuItem(icon: Icons.fact_check_outlined, label: 'Audit Log', builder: (_) => AuditLogScreen(repository: scope.auditRepository)),
      MoreMenuItem(icon: Icons.settings_outlined, label: 'Settings', builder: (_) => BusinessSettingsScreen(controller: scope.settings, auth: scope.auth)),
      MoreMenuItem(icon: Icons.account_circle_outlined, label: 'My Account', builder: (_) => ProfileScreen(auth: scope.auth)),
    ];

List<MoreMenuItem> _accountantMoreItems(AppScope scope) => [
      MoreMenuItem(icon: Icons.price_check_outlined, label: 'Customer Payments', builder: (_) => PaymentsScreen(payments: scope.payments, auth: scope.auth)),
      MoreMenuItem(icon: Icons.local_shipping_outlined, label: 'Purchases', builder: (_) => PurchasesScreen(purchasing: scope.purchasing, suppliers: scope.suppliers, inventory: scope.inventory, auth: scope.auth)),
      MoreMenuItem(icon: Icons.people_outline, label: 'Customers', builder: (_) => CustomersScreen(controller: scope.customers, auth: scope.auth)),
      MoreMenuItem(icon: Icons.factory_outlined, label: 'Suppliers', builder: (_) => SuppliersScreen(controller: scope.suppliers, purchasing: scope.purchasing, cash: scope.cash, auth: scope.auth)),
      MoreMenuItem(icon: Icons.receipt_long_outlined, label: 'Expenses', builder: (_) => CashScreen(controller: scope.cash, initialTabIndex: 1)),
      MoreMenuItem(icon: Icons.account_balance_outlined, label: 'Accounting', builder: (_) => CashScreen(controller: scope.cash, initialTabIndex: 2)),
      MoreMenuItem(icon: Icons.bar_chart_outlined, label: 'Reports', builder: (_) => ReportsScreen(sales: scope.sales, purchasing: scope.purchasing, cash: scope.cash, inventory: scope.inventory, customers: scope.customers, suppliers: scope.suppliers)),
      MoreMenuItem(icon: Icons.account_circle_outlined, label: 'My Account', builder: (_) => ProfileScreen(auth: scope.auth)),
    ];

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.scope});

  final AppScope scope;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tabIndex = 0;
  bool _verifyBannerDismissed = false;

  @override
  Widget build(BuildContext context) {
    // Every controller pings AppSignal after mutating, so this single
    // listener is what keeps every tab (and the FAB) showing fresh data,
    // no matter which feature's controller actually changed it — the same
    // "any mutation repaints everything visible" behavior the old
    // single-AppData object gave for free.
    return ListenableBuilder(
      listenable: AppSignal.instance,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final nav = _navFor(
      widget.scope.auth.currentUser!.role,
      widget.scope,
      (index) => setState(() => _tabIndex = index),
    );
    if (_tabIndex >= nav.screens.length) _tabIndex = 0;

    return Scaffold(
      body: Builder(builder: (context) {
        // Without a verified phone, a forgotten password can't be reset.
        final showBanner = !widget.scope.auth.phoneVerified && !_verifyBannerDismissed;
        final screens = IndexedStack(index: _tabIndex, children: nav.screens);
        if (!showBanner) return screens;
        return Column(
          children: [
            SafeArea(
              bottom: false,
              child: MaterialBanner(
                content: const Text('Verify your phone number so you can reset your password by SMS if you forget it.'),
                leading: const Icon(Icons.phonelink_lock_outlined),
                actions: [
                  TextButton(onPressed: () => setState(() => _verifyBannerDismissed = true), child: const Text('Later')),
                  TextButton(
                    onPressed: () => showVerifyPhoneDialog(context, widget.scope.auth).then((_) => setState(() {})),
                    child: const Text('Verify'),
                  ),
                ],
              ),
            ),
            // The banner already consumed the status-bar inset.
            Expanded(child: MediaQuery.removePadding(context: context, removeTop: true, child: screens)),
          ],
        );
      }),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: nav.destinations,
      ),
      floatingActionButton: nav.fabOnFirstTab && _tabIndex == 0
          ? QuickActionFab(sales: widget.scope.sales, inventory: widget.scope.inventory, customers: widget.scope.customers, cash: widget.scope.cash, auth: widget.scope.auth)
          : null,
    );
  }
}
