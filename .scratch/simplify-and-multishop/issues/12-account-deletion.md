# In-app account deletion
Status: done
Blocked by: 09

Required by Play Store.
- Staff/delivery: delete the login and profile, keep the shop's records, anonymise the name and phone on them.
- Owner: export first (PDF/CSV), confirm twice (type shop name + password, like business reset), delete the shop subtree immediately, then the owner login. No grace period, no server code (decided 2026-10-03). Needs legal/compliance review of retention before release.

## Notes

- Flow: `AuthController.deleteAccount(password, typedShopName)` → `AppScope.deleteAccountData` → `AuthRepository.deleteAccount(password)` (Firebase: re-auth via `verifyPassword`, then `currentUser.delete()`; in-memory removes the login) → `logout`, login screen shows `loginNotice` "Your account was deleted." Online-only (offline = nothing deleted).
- UI: Account → "Delete my account" (everyone; staff text explains anonymising). If the login owns shops, the same dialog lists them, requires typing the first one's name + password. Owners also get Settings → Danger zone → "Export shop data (CSV)" and "Delete shop and account" (dialog has "Export this shop first"). Export = one multi-section CSV (customers + balances, sales, payments, money ledger) of the open shop via share_plus (`lib/app/shop_export.dart`). An owner of several shops must switch shop to export each one.
- Data: for each shop in `accounts/{uid}` with a profile: owner → `wipeShop` (reset's wipe, now parameterised by shop id); else profile patched to `{name: 'Former staff', phone: '', active: false}`. Then one commit: those patches + delete `phones/{phone}` + `accounts/{uid}`. Then the Auth login.
- Rules: self-update of own profile only for non-owners, only `name/phone/active`, only to exactly those values; `accounts/{uid}` delete by itself; `phones/{phone}` delete by the login whose email is that phone. firestore_tests 50 + replay; fixture adds a staff deletion (Shop 2 member) and owner deletion of Shop 2. business_logic: 2 new tests (staff anonymise + sale still resolves + login gone + phone reusable; owner wipes own shop, anonymised in other shop which stays intact, export CSV).
- Ceiling: if data deletion succeeds but the Auth delete fails (network drop in between), the login survives with no shops; signing in says "no profile" and the user can't retry in-app. Rare; fix with a server function if it matters.
- Not done: no notification/audit entry to the shop when staff delete themselves (audit writes need an active profile).

### Personal data remaining after deletion (for privacy policy / compliance review)

- Staff/delivery deletion, in each shop they worked for: the profile doc stays (doc id = the deleted uid, role, permission overrides, `active: false`; name/phone wiped). Names copied onto records at the time stay as the shop's historical records: sales `createdByName`, payments `collectedByName`/`settledByName`/`phoneConfirmedByName`/`disputedByName`/`reversedByName`, orders `placedByStaffName`/`assignedToName` (+ `assignedToId`), audit log entries (`userId` + name in text), notification texts. The uid is pseudonymous once the login is deleted.
- Owner deletion: the owned shops' entire subtrees are deleted (including customer records, customer phones and signatures). Where the owner was staff in other shops, same as staff above. Other staff of a deleted shop keep their own logins plus a stale shop id in `accounts` (no personal data).
- Firebase Auth deletes the login (phone, email alias, password hash); Google's own backup/log retention applies. Crashlytics reports are not deleted by this flow.
- Needs legal/compliance review: retention of staff names on financial records vs. Nepal record-keeping rules, immediate owner deletion of customer financial data with no grace period, and the export being the only copy.
