import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';

enum Permission {
  viewSales,
  createSales,
  editSales,
  cancelSales,
  viewPurchases,
  createPurchases,
  manageInventory,
  adjustInventory,
  viewCustomers,
  manageCustomers,
  viewSuppliers,
  manageSuppliers,
  recordPayments,
  manageExpenses,
  viewAccounting,
  viewReports,
  manageProducts,
  changePrices,
  manageEmployees,
  managePermissions,
  manageSettings,

  /// Be assigned orders, mark them out-for-delivery/delivered, and record
  /// what the customer paid at the door.
  deliverOrders,

  /// Count cash handed over by collectors into the till, and verify
  /// wallet/bank/cheque payments. Collecting and receiving are kept apart.
  reconcileCash,
}

const Map<UserRole, Set<Permission>> defaultRolePermissions = {
  UserRole.owner: {
    Permission.viewSales,
    Permission.createSales,
    Permission.editSales,
    Permission.cancelSales,
    Permission.viewPurchases,
    Permission.createPurchases,
    Permission.manageInventory,
    Permission.adjustInventory,
    Permission.viewCustomers,
    Permission.manageCustomers,
    Permission.viewSuppliers,
    Permission.manageSuppliers,
    Permission.recordPayments,
    Permission.manageExpenses,
    Permission.viewAccounting,
    Permission.viewReports,
    Permission.manageProducts,
    Permission.changePrices,
    Permission.manageEmployees,
    Permission.managePermissions,
    Permission.manageSettings,
    Permission.deliverOrders,
    Permission.reconcileCash,
  },
  UserRole.accountant: {
    Permission.viewSales,
    Permission.createSales,
    Permission.viewPurchases,
    Permission.createPurchases,
    Permission.viewCustomers,
    Permission.manageCustomers,
    Permission.viewSuppliers,
    Permission.manageSuppliers,
    Permission.recordPayments,
    Permission.manageExpenses,
    Permission.viewAccounting,
    Permission.viewReports,
    Permission.reconcileCash,
  },
  UserRole.employee: {
    Permission.viewSales,
    Permission.createSales,
    Permission.viewCustomers,
    Permission.recordPayments,
    Permission.deliverOrders,
  },
  UserRole.delivery: {
    Permission.deliverOrders,
  },
  UserRole.customer: {},
};
