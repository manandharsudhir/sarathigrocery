import 'package:flutter/foundation.dart';

/// Semantic tab-jump callbacks handed down to a dashboard.
///
/// Tab ordering differs per role (index 3 is "Sales" for the owner but
/// "Stock" for an employee), so `AppShell` — which builds the nav — supplies
/// these, and the dashboard never needs to know its own role's tab layout.
/// A null callback means that destination isn't a tab for this role.
@immutable
class DashboardNav {
  const DashboardNav({
    this.openInventory,
    this.openOrders,
    this.openSales,
    this.openCustomers,
  });

  final VoidCallback? openInventory;
  final VoidCallback? openOrders;
  final VoidCallback? openSales;
  final VoidCallback? openCustomers;
}
