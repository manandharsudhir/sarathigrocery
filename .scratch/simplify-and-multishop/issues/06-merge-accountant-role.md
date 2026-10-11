# Fold accountant into staff toggle
Status: done
Blocked by: 05

Roles become owner, staff (employee), delivery.
- Replace the accountant role with a "Can handle cash & accounts" toggle on staff. It grants `reconcileCash` and the money permissions through the existing per-user permission overrides.
- Merge the accountant dashboard sections into the staff dashboard when the toggle is on.

Update rules, rules tests and fixtures.

## Notes

- `UserRole.accountant` removed. The toggle is `EmployeesController.setCashAccess`: it adds/removes `cashPermissions` (permission.dart: accountant defaults minus employee defaults) through the existing `customPermissions` override, so the rules needed no new field, only the role removed from `staff()`, `defaultPermissions` and user creation. Turning it off drops all of `cashPermissions`, even ones granted individually.
- Toggle is on the employee detail screen (staff role only) and saves immediately.
- `AccountantDashboard` deleted; its sections live in `EmployeeDashboard._moneySlivers`, shown when the user has `reconcileCash`. Its duplicate "Today's Sales" and "Owner investment" cards were dropped.
- AppShell: cash staff get More (Customers, Money, Customer Payments, Purchases, Suppliers, Reports) in place of the Customers tab.
- Orders from the staff orders list now always open in the staff view (accountants used to get a read-only view).
- Tests: rules_fixture "accountant" device is now staff 9800000002 with the toggle; rules.test.js `CASHIER` is an employee with the override, plus tests for granting/revoking it and refusing the `accountant` role.
