# Empty states with an action
Status: done

About 25 one-line empty states. Each one gets a button for the obvious next action (for example "No customers yet" + Add customer). Hide the button when the user lacks the permission.

## Notes

- New shared widget `lib/core/widgets/empty_state.dart` (`EmptyState`: message + optional button, hidden when `onAction` is null).
- Buttons added, gated by the same check as each screen's existing FAB, reusing the same flow:
  - Customers: "Add customer" (`manageCustomers` or `createCustomers`, `showCustomerFormSheet`).
  - Sales: "New sale" (`createSales`, not customers, `NewSaleScreen`).
  - Purchases: "New purchase" (`createPurchases` and at least one supplier, `NewPurchaseScreen`).
  - Expenses tab: "Add expense" (`showAddExpenseSheet`; the screen is only reachable by roles that manage expenses, same as its FAB).
  - Staff orders: "New order" (`createSales`, `StaffNewOrderScreen`), only on the "All" filter.
- Skipped, no sensible action or already covered: notifications, audit log, deliveries, my collections, payments-screen status messages, dashboard summaries ("all caught up", no staff sales, no transactions, no activity), statement lines, product search, quick-action customer picker, customer dashboard (Browse Products button sits right above), customer orders and cart (customer screens are removed in ticket 2), supplier detail (payment button already shown above; new purchase there would need extra wiring).
- Inventory, suppliers and employees lists have no empty-state text today; not added here.
