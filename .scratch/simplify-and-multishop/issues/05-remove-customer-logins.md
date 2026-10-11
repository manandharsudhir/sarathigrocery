# Remove customer logins
Status: done
Blocked by: 04

Delete:
- customer screens (browse, cart, checkout, customer orders, customer dashboard, notifications for customers)
- `CreateCustomerLogin` and `Customer.hasAppLogin` usage
- `deliveryCodes`, `codeChecks` and the code-check steps in Deliver & Collect
- the customer branch of `_loadPlan`
- the customer rules and their firestore_tests

Customer confirmation is signature or phone only. Update business_logic_test, the rules fixture scenario and CLAUDE.md.

## Notes

- Deleted: customer dashboard, products browse, cart, checkout, customer orders screens, `CreateCustomerLogin`, the "create app login" sheet. `UserRole.customer`, `AppUser.linkedCustomerId`, `UserRepository.userForCustomer`, `CustomerOrder.placedByUserId`, `Customer.hasAppLogin`, `CustomerPayment.deliveryCode`/`customerConfirmedAt`, the order-repo cart and `deliveryCodes`/`codeChecks` collections are gone. Old JSON with those fields is ignored.
- `PlaceOrder` now takes the item list directly (staff only, `placedByStaffName` required). Customer-targeted notifications (order status, receipt, undo) are removed.
- Deliver & Collect requires a signature for every customer. Unsigned (counter) payments go to Issues immediately (the 24-hour grace for app users is gone).
- Rules: customer reads/order placement, `deliveryCodes`, `codeChecks`, the delivery-code check on payments and the customer confirm/dispute updates are removed. Users can no longer be created with role `customer`.
- Tests: flutter 38 pass; emulator 29 pass (28 rules cases + replay). Fixture regenerated.
