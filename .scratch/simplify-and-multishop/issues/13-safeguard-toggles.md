# Per-shop safeguard toggles
Status: done
Blocked by: 08

Settings toggles, default off: signature at the door, phone confirmation of unsigned payments, cash handover + cash missing tracking, online-only collection.
- When the first staff account is created, offer to turn them on with one tap.
- The rules read the shop's settings and enforce whatever is on. Add rules tests for each on/off pair.

## Notes

- `Safeguard` enum (business_settings.dart) + settings doc field `safeguards` (list of names, missing = off), same pattern as `features`. `SettingsController.guards/setSafeguard/enableAllSafeguards`. Settings → "Safeguards" (owner only), 4 switches with one-line hints. Use cases/controller read them via a `bool Function(Safeguard)` closure from `AppScope`.
- First staff prompt: `EmployeesScreen` (now takes `settings`) shows "Turn on safeguards for staff?" (Turn on / Not now) after the owner adds an account, when it's the only non-owner account and all safeguards are off.
- Off behaviour: signature optional at Deliver & Collect (receipt recorded only if signed); unsigned payments stored with `autoConfirmed: true` (new immutable `CustomerPayment` field, counts as customer-confirmed, never in Issues; turning the toggle on later doesn't re-flag them); every collection settles at once for the full amount by its collector, no separation of duties (also for later settles of old pending ones); Deliver & Collect isn't awaited, the queue commits it.
- Deliver & Collect no longer commits the takeover `assign` separately: takeover + delivery + payment are one synchronous turn = one batch online or offline (the separate commit only existed for the delivery-code checks). Online-only mode wraps that same batch in the transaction.
- Rules: `guarded(name)` reads `shops/{id}/settings/business`. signature on → delivered order needs `receivedSignature`, order payment needs `signature`. phoneConfirm on → `autoConfirmed` payments refused; phone confirm of an `autoConfirmed` one always refused. handover on → as before; off → any collector may create a payment settled by themselves for the full amount, `reconcileCash` holders may settle their own, and a deliverer may create a `collection` ledger entry only for a payment created in the same batch and settled by them for that amount. onlineOnly isn't enforceable (a queued write looks the same).
- Tests: business_logic 44, full flutter suite 47 (new: defaults/sync, all-off offline single-batch flow, each toggle on its own); `TestBusiness.create(safeguards: true)` keeps existing strict coverage. firestore_tests 48 (+4 safeguard on/off cases; seed has a settings doc with all on). Fixture: day runs with all on, plus an all-off segment (unsigned offline-style delivery settled by the delivery person, unsigned counter payment) before staff admin.
- Risk: with online-only off, a server rejection of a queued delivery is only reported (Crashlytics) and rolled back by snapshots, as for any write; the user saw "Delivered".
