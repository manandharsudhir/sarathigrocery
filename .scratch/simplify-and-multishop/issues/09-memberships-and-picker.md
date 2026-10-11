# Memberships + shop picker
Status: done
Blocked by: 08

`memberships/{uid}_{shopId}` → role and permission overrides. One login (phone) can hold many memberships.
- Adding staff by a phone that already has a login adds a membership. Today this fails with "already registered".
- The shop picker after login shows only when there are 2 or more memberships.

## Notes

- Membership model is 08's (shop-scoped profile + `accounts/{uid}.shopIds`); no `memberships` collection.
- Existing-login lookup: Firebase client SDK can't resolve a uid by email without signing in, so every login writes top-level `phones/{phone}` = `{uid}` (`UserRepository.registerPhone`, from `AuthController._enter`). Rules: create/update only if `request.auth.token.email == phone + '@sarathigrocery.app'` and `uid == request.auth.uid`; `get` for any signed-in user; no list/delete. `CreateEmployeeAccount` looks the phone up first: found → profile in this shop + append to their account, password unused, UI says "Added — they sign in with their existing password."; not found → new login as before. A login that exists but never signed in (no phone doc) gets "Ask them to sign in once, then add them again". `AuthRepository`/`InMemoryAuthRepository` unchanged.
- Privacy: any signed-in user (any shop) can check whether a given phone has a login and learn its uid — one `get` per guess, no listing. The uid alone grants nothing (access is the shop profile). Note for the privacy-policy review.
- Append-only accounts: new `ArrayUnionOp` (`RemoteStore`, Firestore `FieldValue.arrayUnion`, coalesced per document like increments; in-memory; `ShopScopedStore`; fixture + replay). Used by `UserRepository.add` and `createShop`, so `SetUpBusiness` no longer reads the owner's shop list.
- Picker: `auth.shops` (active profiles only; names read from each shop's settings, only when 2+). 2+ → `ShopPickerScreen` (list + Log out) until `pickShop`; Account → "Switch shop" (`switchShop` detaches mirrors, back to picker). Setup opens the new shop directly. Last choice per device not remembered.
- Tests: business_logic 38 (new: staff of A added to B as delivery, picker, B-only data, switch to A, unused-login refusal); firestore_tests 42 cases + replay (new: phones claim/overwrite/list). Fixture records `actorPhone` (replay sets the token email) and adds a second shop adding the employee by existing phone.
