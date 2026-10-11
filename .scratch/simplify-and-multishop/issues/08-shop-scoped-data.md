# Shop-scoped data layout
Status: done
Blocked by: 07

Move every collection under `shops/{shopId}/`. Scope it at the `RemoteStore` level (prefix paths once there), so repositories don't change.

Delete the `meta/setup` singleton logic. Reset/wipe deletes only `shops/{shopId}`. Rewrite the rules as membership checks. Port all firestore_tests and the replay fixture.

## Notes

- Scoping: `AppScope` wraps the given store in `ShopScopedStore` (`remote_store.dart`), which prefixes `shops/{shopId}/` to every collection except `accounts` and `shops`. `shopId` is set by `useShop` at login (`AuthController._enter`: first shop in `accounts/{uid}.shopIds` where the account still has a profile) and at setup. Repositories and use cases are unchanged. `InMemoryRemoteStore` keys collections by full path.
- `meta/setup` is gone. `SetUpBusiness` makes `shops/{nextId('S')}` + owner profile + settings + account append in one commit; sample data is a second commit. Any login may create shops.
- Staff creation writes `accounts/{uid} = {shopIds: [shopId]}` as a full list (fine while staff logins are always new). Ticket 09 (existing logins joining) needs an arrayUnion write; the rules already accept an arrayUnion append (tested).
- Reset deletes only the current shop's subtree, then owner profile + shop doc + the owner's account entry in the final commit. Staff accounts keep a stale shop id; login skips it.
- Removed legacy-data code: `migrateLegacyCosts`, `SyncedCollection.clearField`, and the "never billed" owner item (`uninvoicedDeliveries`), which only served pre-invoicing orders.
- Rules: `match /shops/{shopId}` with scoped helpers (`memberOf`, `activeIn`, `canIn`, ...); per-collection logic unchanged. A user may read their own profile in any shop (even missing/deactivated) so login can probe.
- Tests: business_logic two-shop isolation + reset; firestore_tests 40 cases (+ replay) incl. shop setup/takeover, shop isolation, accounts appends.
