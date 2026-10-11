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

  /// Add new customers (credit limit starts at 0 until someone with
  /// manageCustomers sets it). Sales staff have this.
  createCustomers,

  /// Be assigned orders, mark them out-for-delivery/delivered, and record
  /// what the customer paid at the door.
  deliverOrders,

  /// Count cash handed over by collectors into the till, and verify
  /// wallet/bank/cheque payments. Collecting and receiving are kept apart.
  reconcileCash,

  /// Price a sale/order line below its minimum selling price (clearance,
  /// damaged stock). Owner by default; staff via a per-user toggle. Every
  /// such line is audited and the owner notified.
  sellBelowMinimum,
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
    Permission.createCustomers,
    Permission.sellBelowMinimum,
  },
  UserRole.employee: {
    Permission.viewSales,
    Permission.createSales,
    Permission.viewCustomers,
    Permission.recordPayments,
    Permission.deliverOrders,
    Permission.createCustomers,
  },
  UserRole.delivery: {
    Permission.deliverOrders,
  },
};

/// What the "Can handle cash & accounts" staff toggle adds on top of the
/// employee default, stored as a per-user `customPermissions` override.
/// (This was the accountant role.)
const Set<Permission> cashPermissions = {
  Permission.viewPurchases,
  Permission.createPurchases,
  Permission.manageCustomers,
  Permission.viewSuppliers,
  Permission.manageSuppliers,
  Permission.manageExpenses,
  Permission.viewAccounting,
  Permission.viewReports,
  Permission.reconcileCash,
};
