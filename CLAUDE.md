# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Flutter version management

This project pins Flutter via FVM (`.fvmrc` → 3.44.7). Always prefix Flutter/Dart commands with `fvm`:

```
fvm flutter pub get
fvm flutter run
fvm flutter test
fvm flutter test test/business_logic_test.dart   # single test file
fvm flutter analyze
fvm flutter build <platform>
```

Running bare `flutter`/`dart` may use a different SDK version than the one this project targets.

## Linting

`analysis_options.yaml` includes `package:flutter_lints/flutter.yaml` with no project-specific rule overrides.

## Platforms

Platform scaffolding exists for android, ios, linux, macos, windows, and web. Firebase is configured (`flutterfire configure`) for android, ios, web only, and `main.dart` throws on macos/linux/windows. iOS deployment target is 15.0 (Firebase SPM minimum). The Android Crashlytics Gradle plugin (3.0.6) is applied.

## Project state

Production Flutter app on Firebase (Firestore + Firebase Auth + Crashlytics), built so Firebase can be replaced by a custom backend (planned). All 10 phases of `.claude/docs/detailed_requirement.md` are implemented, plus: first-run business setup, customer add/edit, change password, email password reset.

**Accounts.** Login is email + password through `AuthRepository` (plain Firebase email/password accounts; emails stored trimmed + lowercased, `normalizeEmail`). No SMS anywhere: Firebase phone auth needs the paid Blaze plan, and the project stays on the free Spark plan. Phone is just a contact field on the profile (not unique, not verified). The account id (Firebase uid) is the `AppUser` document id, and credentials never touch Firestore. **Multi-shop:** all shop data lives under `shops/{shopId}/`. The profile `shops/{shopId}/users/{uid}` (with `email`) is the membership (role + overrides); top-level `accounts/{uid}` = `{shopIds}` tells login where to look. `AuthController._enter` collects the shops with an active profile (`auth.shops`): one opens directly, 2+ show `ShopPickerScreen`, and Account offers "Switch shop". A login whose `accounts` doc lists no shop sets `auth.needsSetup`, and `AuthGate` shows `SetupScreen` to finish sign-up. **Sign-up** (login screen → "New shop? Sign up", `SetupScreen`): email + password (`AuthRepository.signUp` creates, signs in, sends Firebase's verification email) → "I've verified" (`reloadEmailVerified`) → shop + owner name + phone. Leaving midway is fine: logging in later resumes at the verify/shop step. `SetUpBusiness` needs a signed-in, email-verified login (rules: `request.auth.token.email_verified`); one commit creates `shops/{nextId('S')}` (`ownerId`, `createdAt`), the owner profile, settings, and appends the shop to the owner's account. Account → "Set up another shop" reuses the same login. The owner then adds staff (Employees) by email + phone + temporary password; staff emails are never verified, which only matters if they later set up a shop of their own. `accounts` entries are only ever appended with `ArrayUnionOp` (`SyncedCollection.union`). Every login writes `emails/{email}` = `{uid}` (rules: only the account whose token email is that email; any signed-in user may `get` one, never list), so adding staff by an email that already has a login adds that login to this shop with its existing password (`CreateEmployeeAccount`); a login that never signed in can't be found yet. Customers have no logins: they are records the shop keeps. Minimum password length is 8 (`passwordProblem`).

**Password reset.** "Forgot password" sends Firebase's reset email (`sendPasswordReset`); the new password is set on the page the link opens. Unknown emails are silently accepted (no account enumeration). Staff whose email is fake or unread can't reset: the owner re-adds them under another email (no Admin SDK on Spark).

**Enforcement.** `firestore.rules` enforces roles/permissions server-side and mirrors `Permission` defaults plus per-user overrides. Everything is under `match /shops/{shopId}` and checks only that shop's profile of the caller, so nothing crosses shops. `accounts/{uid}`: read by its owner only; it only gains a shop the account has a profile in (added by itself or that shop's `manageEmployees` holder, appended at the end), and only the account itself removes entries. Staff read the whole shop; every write needs the permission the UI checks. Delivery staff read customers plus their assigned orders and own collections. Ledgers and the audit log are append-only. The UI's `auth.can(...)` checks are UX only; the rules are the real gate. Tests: `firestore_tests/` (58 cases incl. cross-shop denial, journal and VAT numbering, plus the replay of real app writes, emulator).

**Monitoring.** `reportError` (`lib/core/services/error_reporter.dart`) is set to Crashlytics in `main.dart` (not on web). Uncaught Flutter/platform errors are recorded as fatal. Collection is off in debug builds.

## Orders, payments and verification

Money only moves through records that can't be edited; balances are backed by them.

- **Delivery invoices.** `AdvanceOrderStatus` → delivered deducts stock AND records an invoice (credit `Sale` with `orderId`) and adds it to `outstandingBalance`. Any payment is a separate `CustomerPayment` (`customers` feature, collection `customerPayments`).
- **Safeguards** (Settings → Safeguards, owner only; `Safeguard` enum, settings doc field `safeguards`, all **off** by default). Adding the first staff account offers to turn all four on. The rules read `settings/business` (`guarded(name)`) and enforce what's on; when off they allow the simpler path. Read in the app through a `bool Function(Safeguard)` closure from `AppScope`.
  - `signature`: Deliver & Collect requires the customer's **signature** (`core/widgets/signature_pad.dart`, stored on the order as `receivedSignature` and on the payment). Rules: a delivered order and an order payment must carry one. Off: optional.
  - `phoneConfirm`: unsigned payments go to Issues; someone with `reconcileCash` (never the collector) phones the customer and records `confirmByPhone` or `disputeOnBehalf` (`RespondToPayment`). Off: unsigned payments are created `autoConfirmed` (rules refuse that while on) and count as confirmed. A signed payment is always confirmed.
  - `handover`: business-side "settled" by someone with `reconcileCash` counting it in (`SettlePayment`); collectors can't receive their own (owner excepted); counted < collected = "cash missing", audited and notified. Off: every collection settles at once for the full amount by its collector (rules let delivery staff write that one `collection` ledger entry), no separation of duties. Either way, `reconcileCash` holders collecting settle immediately, and the counted amount enters the ledger on its account (`ledgerAccountFor`: cash / wallet / bank for bank+cheque).
  - `onlineOnly`: Deliver & Collect commits with `WriteQueue.flush(requireOnline: true)` (a Firestore transaction: never queued offline, fails with `OfflineException`, every mirror rolls back via `SyncedCollection._rollback`). Off: it's queued like any write. App-only; rules can't tell a queued write.
- **Deliver & collect** (`OrderingController.deliverAndCollect`) writes takeover (`assign`, for owner/employee delivering an order not assigned to them, since the rules only let the assigned deliverer invoice) + receipt + delivery + invoice + payment (+ settlement) in one synchronous turn, so it is one atomic batch either way. Don't add an `await` inside it before the last write.
- **Allocation** is derived, never stored: `buildStatement` (`customer_statement.dart`) pays the linked order first, then the oldest bills. The opening balance counts as the oldest. `Customer.openingBalance` (fixed at creation) lets the statement prove `outstandingBalance == opening + bills − payments`. `balanced == false` means something moved a balance outside these flows, and it's surfaced on the owner dashboard and on the statement.
- **Corrections:** owner-only `ReversePayment`, at any time. The payment stays visible, marked reversed, and the balance goes back up. If it was already settled, a `CashEntryType.refund` entry takes the counted amount back out of its account.
- **Cash book:** `CashLedgerEntry.account` is a money account id: `cash`, `bank`, `wallet`, or a named `bank:<name>`/`wallet:<name>` (Settings → Accounts, `moneyAccountIds`). Use `isOutflow`/`signedAmount`; don't re-derive signs from `type`. Transfers, capital, drawings, loans, dividends, VAT paid and "other payments" are `moneyIn`/`moneyOut` lines (a transfer is one of each). Sales, purchases, supplier payments and expenses each pick their account.

## Accounting (double entry) and VAT

The cash book stays the subledger; the general ledger is the `journal` collection (`features/accounting`). Ask an accountant before changing any posting.

- **`Books`** (`accounting/domain/books.dart`) is the only place that maps business events to debits/credits: every use case that moves money or stock calls it **in the same synchronous turn** (same batch): `RecordSale`, `ReverseSale`, `AdvanceOrderStatus` (invoice), `CreatePurchase`, `RecordPurchaseReturn`, `RecordSupplierPayment`, `AdjustStock`, `UpdateProduct` (cost change → revaluation), product/customer creation (opening stock / old udharo → capital), `RecordPayment`/`SettlePayment`/`ReversePayment`, and `CashController`'s money actions. **A new money/stock write path needs a `Books` call** or the "books balanced" checks fail.
- `JournalEntry.lines`: account id → signed amount (+debit/−credit), always summing to zero (checked in `Books.post`; rules can't sum). Entries are append-only; corrections are new entries. Record-backed entries use deterministic ids (`sale-<id>`, `cogs-<id>`, `pay-<id>`, `settle-<id>`, `*-rev-<id>`), so nothing is booked twice.
- **Chart of accounts** (`accounts.dart`): string ids, no collection. Core ids plus families `capital:<owner>`, `drawings:<owner>`, `loan:<lender>`, `expense:<category>`, `bank:<name>`, `wallet:<name>`. `collectors` = money customers paid that isn't counted in yet; `toClassify` = "other payments" for the accountant (equipment, deposits).
- **Stock cost** is weighted average per base unit (`CreatePurchase`), set by purchases: the product form asks for cost only with opening stock (goods already on hand); afterwards it is read-only, with an owner-only "Correct cost" (booked as a revaluation). A sale before the first purchase has no cost: it shows in `AccountingController.salesWithoutCost` and its COGS is booked once a purchase gives the product a cost. Sale lines snapshot `unitCost`. Delivery staff can't see costs, so their invoices post `sale-<id>` only; a staff device posts `cogs-<id>` later (`Books.postMissingCosts`, run on connect and when Accounts opens).
- **Checks** (`AccountingController.checks`/`booksBalanced`): journal vs cash book per money account, receivables vs customers, payables vs suppliers, collectors vs pending payments, stock vs Σ qty×cost. Shown on the Accounts Simple view and as an owner Needs Attention row.
- **Owners & year end:** `BusinessSettings.owners` (name, %; set-up makes the owner 100%) splits opening capital. Opening balances (one time, owner, locked once anything but opening entries exists), manual adjustments (owner, balanced, no money accounts, reason), and `closeYear` (owner: P&L and dividends → retained earnings, then `closedThrough`; rules refuse any journal entry dated on/before it and never let it move back). Owner-only journal kinds are listed in `firestore.rules` (`capital`, `drawing`, `drawingReturn`, `loan`, `loanRepaid`, `dividend`, `manual`, `opening`, `close`); delivery staff may only write `sale`, `payment`, `settlement`.
- **Settings saves use `copyWith`**: building a fresh `BusinessSettings` drops fields (it once reset `closedThrough`, which the rules caught).
- **Periods / BS calendar:** `core/utils/bs_date.dart` embeds BS month lengths 2075–2090 (from `nepali-date-converter` 3.4.0; later years are projections, so update the table when the calendar is published). Fiscal year = Shrawan 1 – Asar end (`fiscalYear`, `fiscalYearRange`). Today's profit on dashboards and P&L by period come from the journal (`Statements`), never from all-time totals.
- **VAT** (owner, Settings → VAT: `vatRegistered`, `panNumber`, rate `taxPercent` default 13, `pricesIncludeVat`): `VatTerms`/`vatOn` (`sales/domain/entities/vat.dart`); `Product.vatExempt` lines carry no VAT. Sales and orders store `vatAmount`, `vatIncluded`, `exemptAmount`; postings split VAT to `vatPayable` / `vatInput`. In a VAT shop **every sale is a numbered tax invoice**: `SalesController.sell` / `OrderingController.deliverAndCollect` read the next number (`BillNumbers`, `counters/{invoice|credit}-<BS FY>` = `{next}`), take it in the same batch, and commit online-only, retrying if the rules refuse a number another device took. `recordSale`/`advanceOrderStatus(delivered)` without a number throw `StateError` in a VAT shop. Cancel/return of a tax invoice issues a numbered `CreditNote` (`SalesController.reverse`). Purchases record supplier bill no./date/VAT. `VatBooksScreen`: Sales Book, Purchase Book (by BS month), VAT payable, `CashController.vatPaid`. IRD real-time billing (CBMS) is not implemented. Bill format must be confirmed by an accountant.
- **Exports:** `lib/app/accountant_export.dart`: CSV (P&L, Balance Sheet, Trial Balance, journal, VAT books) + PDF statements for a period, shared from Accounts.
- **Units, packs and minimum prices.** Retail and wholesale share one shop and one stock. A product counts stock, cost (`purchasePrice`) and `reorderLevel` in its base `unit` (kg, litre, bottle, ...), as decimals. `Product.packs` (`ProductPack`: label, size in base units, price) are the bigger ways it's sold/bought (50 kg sack, box of 12). `sellUnits` = base unit (`unitPrice`) + packs. On the product form the owner enters a **main unit** (`Product.primaryUnit`, e.g. sack: cost, opening stock and low stock are entered per main unit; stock shows as "8.5 sack (425 kg)") and other units as "1 sack = 60 kg" / "1 box = 12 bottle"; `planUnits` (`unit_setup.dart`) turns that into the smallest unit as base plus packs. `Product.saleUnit` is where a sale line starts; purchases start in the main unit. With stock on hand, the base unit and existing conversions can't change (units can be added). Each unit's price is its **minimum** selling price: sellers type any line price at or above it. Prices are optional: until set, the floor is the cost (`Product.floorFor`); with neither price nor cost (never purchased) the product can't be sold (`UnpricedProductException`). Purchases pre-fill new minimum prices at cost + `BusinessSettings.marginPercent` (only where none is set or it's below the new cost) and notify the owner of products still unpriced or priced below cost (`PurchasingController.notifyPricesNeeded`). Sale/order/purchase lines carry `unit` + `size` (`baseQty` = qty × size moves stock). Below the minimum needs `Permission.sellBelowMinimum` (owner; staff via the employee toggle), else `RecordSale`/`PlaceOrder` throw `BelowMinimumPriceException`; allowed ones are audited and the owner notified (`auditBelowMinimum`). App-only (rules can't loop over lines). There is no discount %: the line price is the negotiation. Purchases take cost per unit (stored per base unit) and, for `manageProducts` holders, new minimum prices. `describeQty` renders "1,250 kg (25 sack)"; `formatQty` drops trailing zeros. Sale lines snapshot `unitCost` so profit doesn't move when cost changes; delivery staff invoicing an order can't see costs, so those lines fall back to the current cost.
- **Cost prices** live in staff-only `productCosts/{productId}` (same `Product` objects, merged by `ProductRepositoryImpl._costs`). The rules reject `purchasePrice` on `products`. Delivery staff see `purchasePrice == 0`.
- **Business reset** (Settings → Danger zone, owner only): the owner must type the business name and re-enter their password (`AuthRepository.verifyPassword`), and it runs online-only. `wipeShop(ownerId, shopId)` in `AppScope` lists every collection of that shop via `RemoteStore.listIds`, deletes all of it, and in the final commit deletes the owner's profile and the `shops/{id}` doc and removes the shop from the owner's account. Other shops are never touched; staff accounts keep a stale entry that login skips. The rules give the owner `delete` on every collection of their own shop solely for this. Logins (Firebase Auth) survive; logging in again with the same email resumes sign-up (`needsSetup`) and reuses the login. When adding a collection, it's covered automatically if it's in `AppScope`'s `collections`; add an owner `allow delete` rule for it.
- **Account deletion** (Play Store; Account → "Delete my account", owners also Settings → Danger zone with "Export shop data (CSV)", `lib/app/shop_export.dart`): `AuthController.deleteAccount` checks the password (and, if the login owns shops, the first owned shop's typed name), then `AppScope.deleteAccountData` runs `wipeShop` for every owned shop and, in one online-only commit, anonymises the profile in shops where it's staff (`kFormerStaffName`, phone '', email '', `active: false`; doc kept so user ids resolve) and deletes `emails/{email}` + `accounts/{uid}`; then `AuthRepository.deleteAccount` (re-auth + delete). Immediate, no grace period. Rules: that exact self-update (non-owners only) and self-delete of own emails/accounts docs. Copied names on sales/payments/audit stay.
- **Audit entries** carry `userId`, which the rules require to equal the signed-in account.
- **Co-owners / founding owner:** several profiles may have `UserRole.owner` (co-owners, all owner rights). The **founding owner** is `shops/{id}.ownerId` (`AuthController.founderId`/`isFounder`; rules `isFounder()`): only they erase data (every `allow delete` is `isFounder()`; reset, account deletion of a founded shop), add co-owners (`CreateEmployeeAccount(byFounder:)`, Employees → role "Co-owner"), switch co-owners off/on, and hand the role to an active co-owner (`EmployeesController.handOverFounding`, shop doc `ownerId` update). A co-owner leaves via `AuthController.leaveShop` (self `active: false`; flushed before sign-out). A founder with active co-owners can't delete their account until they hand over (`AppScope.deleteAccountData`); a non-founder's deletion only anonymises them. Co-owners are partners in `BusinessSettings.owners`; a partner leaves that list only once their capital + drawings net to zero (`AccountingController.saveSetup`).
- **Roles:** `UserRole.delivery` has `deliverOrders` only. It sees customers and its assigned orders/collections (`DeliveriesScreen`, `MyCollectionsScreen`). Owner and employee also have `deliverOrders`. `reconcileCash`: owner, and staff with the "Can handle cash & accounts" toggle (`EmployeesController.setCashAccess`, which adds `cashPermissions` via the per-user `customPermissions` override; there is no accountant role). An order is not debt: placing one never checks credit. The limit is checked when goods go out on credit: delivery (`AdvanceOrderStatus._invoice`, net of what's paid at the door) and udharo counter sales (`RecordSale`). Past the limit it's allowed, warned in the form, the sale is `flaggedForApproval` (shown as "Over credit limit"), audited, and the owner notified.
- **Orders** are taken by staff for a customer (phone/WhatsApp/in person: `placeOrderFor`, Orders → New Order).
- Receipts and statements share as PDF (`customers/presentation/pdf/payment_documents.dart`, packages `pdf` + `share_plus`).
- **Sales staff create customers** (`Permission.createCustomers`: owner, employee). Without `manageCustomers`, the credit limit and opening balance are forced to 0 (the rules check this too) and the owner is notified.
- `FirestoreRemoteStore.commit` coalesces multiple writes to one document into one write, because rules judge each write separately (e.g. create payment + settle it).

## Backend seam

Two interfaces are the entire backend contract. Only `FirestoreRemoteStore`, `FirebaseAuthRepository`, `main.dart` and `firestore.rules` know about Firebase:

- `RemoteStore` (`lib/core/data/remote_store.dart`): `watch(collection, {id, where})`, `get`, and `commit(List<WriteOp>)` (atomic). Impls: `FirestoreRemoteStore`, `InMemoryRemoteStore` (tests; keyed by full path like Firestore). `AppScope` wraps whichever it gets in `ShopScopedStore`, which prefixes `shops/{shopId}/` to every collection except `accounts`/`shops`, so repositories use plain names. `shopId` is set at login/setup (`useShop`). On a custom backend these map to GET/stream, GET by id, and `POST /commit`. The server must then enforce what `firestore.rules` does today.
- `AuthRepository` (`lib/features/auth/domain/repositories/auth_repository.dart`): sign in/out, sign up, create account, change password, email verification, reset email. Impls: `FirebaseAuthRepository`, `InMemoryAuthRepository` (tests; `verifyEmail` / `resetPasswordFor` stand in for clicking the emailed links, `sentResets` records reset requests).

`main.dart` passes the Firebase pair into `AppScope(store:, authRepository:)`, and `AppScope()` with no args is fully in-memory.

Repositories stay **synchronous** on top of `SyncedCollection<T>` (`lib/core/data/synced_collection.dart`). It holds a local mirror of one collection, loaded at login per role (`AppScope._loadPlan`) and kept live by `watch`. Writes go through the shared `WriteQueue` (`lib/core/data/write_queue.dart`), which batches every write made in one event-loop turn into one atomic commit. Since use cases are synchronous, each operation (e.g. `RecordSale`) is all-or-nothing on the server without the domain layer knowing. JSON mapping lives next to each repo impl (`toJson`/`fromJson`/`merge`). Rules when touching data:

- Every mutation of a persisted entity must go through its repository (`add`/`save`/`increment`). A direct field mutation changes only this device.
- Don't `await` inside a use case between writes that must be atomic. An `await` splits the batch.
- `_loadPlan` and `firestore.rules` must agree. A watch the rules reject fails that role's login. `firestore_tests` has an "app load plan" test mirroring `_loadPlan`: update both together.
- `save()` sends only fields that differ from the server's last copy (`serverDoc`). That keeps rule `changedOnly(...)` checks honest even for older documents that lack newer fields. Use `patch` for raw partial writes.
- No data migrations: multi-shop started from fresh data.
- **Rules vs. real writes:** `test/rules_fixture_test.dart` drives a full business day through the app on separate devices (`InMemoryAuthRepository.forDevice()`), records every commit with its author, and writes `firestore_tests/fixtures/app_writes.json`. `firestore_tests/replay.test.js` replays it against the rules in the emulator. Run the Dart test first, then the emulator suite. When adding a write path, add it to that scenario.
- Remote snapshots are merged **in place** (entities reference each other by object). New mutable fields need adding to `merge`.
- Concurrently changed numbers (stock, reserved qty, customer balance, supplier payable) use `increment` and are listed in `counters`.
- Cross-references are stored as ids and resolved via `byId` in `fromJson`. Unresolved docs are retried automatically.
- Logout detaches and clears every mirror.

## Architecture: feature-first Clean Architecture

Refactored from an earlier single-`AppData`-god-object design (per `.claude/docs/architecture.md`) into 14 features, each with (where it owns real state) `domain/{entities,repositories,usecases}` → `data/repositories` → `presentation/{controllers,pages}`. No DI framework — `lib/app/injection.dart`'s `AppScope` is a small hand-written composition root that also picks the backend (see "Backend seam").

```
lib/
├── app/                    composition root + cross-feature UI glue
│   ├── app.dart            SarathiGroceryApp, AuthGate (login vs shell)
│   ├── injection.dart       AppScope — constructs every repo + controller once, picks backend
│   ├── sample_data.dart     optional starter catalogue offered at first-run setup
│   ├── navigation/app_shell.dart   per-role bottom nav, built from AppScope
│   └── widgets/            QuickActionFab, MoreMenuScreen, dashboardActions —
│                           these compose several features' screens/controllers,
│                           so they don't belong to any single feature
├── core/
│   ├── data/               RemoteStore (backend seam), WriteQueue, SyncedCollection, Firestore impl
│   ├── services/error_reporter.dart  reportError hook (Crashlytics in main.dart)
│   ├── utils/id_generator.dart    nextId('P') — time-ordered, multi-device-unique ids
│   ├── utils/formatters.dart      formatNpr (Nepali digit grouping), formatDate, formatDaysAgo, formatQty
│   ├── utils/bs_date.dart         Bikram Sambat calendar, fiscal year, formatBs
│   ├── services/app_signal.dart   see "Cross-feature reactivity" below
│   └── widgets/            MetricCard, StatusBadge — used by 3+ features
└── features/
    ├── auth/               UserRole, Permission, AppUser, login, AuthController
    ├── inventory/          Product, categories, stock adjustments
    ├── customers/          Customer, credit status, CustomerPayment, statements, handover
    ├── suppliers/          Supplier, payable
    ├── purchasing/         Purchase, receiving stock, purchase returns
    ├── sales/              Sale, record/cancel/return, invoices
    ├── cash/               cash book, expenses, transfers, owners' money (Money screen)
    ├── accounting/         journal, Books (postings), Statements, Accounts / VAT books screens
    ├── ordering/           CustomerOrder, order lifecycle, delivery assignment
    ├── employees/          employee accounts + permission editing (uses auth's UserRepository)
    ├── settings/           business settings
    ├── notifications/      presentation-only consumer of NotificationRepository (no controller — see below)
    ├── audit/              presentation-only consumer of AuditRepository (no controller)
    ├── reports/            presentation-only: 13 report views reading other features' controllers directly
    └── dashboard/          presentation-only: 3 role dashboards composing 5-6 controllers each
```

**Cross-feature dependencies are normal, not violations.** `Product` is owned by `inventory`, but `sales`, `purchasing`, and `ordering`'s use cases legitimately take `ProductRepository` as a collaborator (e.g. `RecordSale` needs `ProductRepository` + `CustomerRepository` + `CashRepository` + `AuditRepository` + `NotificationRepository`). This is domain-depends-on-domain of a *different* feature, which Clean Architecture allows — it's not the same as the presentation/data layers reaching across features.

**Skipped deliberately, per `architecture.md`'s own "don't force unnecessary abstraction" rule:**
- No `usecases/` for plain CRUD (e.g. `createProduct`, `createSupplier`) — the controller calls the repository directly. Use cases exist only for operations with real cross-repository logic (`RecordSale`, `PlaceOrder`, `AdjustStock`, ...).
- `notifications`, `audit`, `reports`, `dashboard` have no `domain`/`data` of their own — they're read-only views over other features' repositories/controllers, so there's nothing to abstract.
- Repository interfaces have one impl each; backend swapping happens one level lower, at `RemoteStore`/`AuthRepository`. The interfaces still exist per `architecture.md` so `domain/usecases` don't import `data/repositories`.

### Cross-feature reactivity — `AppSignal`

Every controller is its own `ChangeNotifier`; a mutation in `SalesController` does not notify `CashController`'s listeners even though `RecordSale` writes to the cash ledger. `lib/core/services/app_signal.dart` is a single app-wide `ChangeNotifier` with one method, `ping()`, that every controller's mutating method calls in addition to its own `notifyListeners()`. **`AppShell`'s build wraps everything in `ListenableBuilder(listenable: AppSignal.instance, ...)`** — that one listener is what keeps every visible tab showing fresh data no matter which feature's controller changed it, replacing the "any mutation repaints everything" behavior the old single-`AppData` object gave for free. When adding a new mutating controller method, call `AppSignal.instance.ping()` alongside `notifyListeners()` unless you're certain nothing outside the controller's own screen displays that data. Remote changes (another device) arrive via `SyncedCollection`, which also pings `AppSignal`.

Screens reached via `Navigator.push` (not part of `AppShell`'s `IndexedStack`) are **not** covered by that top-level listener. If a pushed screen shows data mutated by a controller other than the one it already listens to, it needs its own `ListenableBuilder`/`Listenable.merge([...])` — see `SupplierDetailScreen` for an example merging three controllers. This exact gap (dashboards reading 6 controllers, listening to none) was a real bug caught during the refactor, found by running the app on an emulator, not by `flutter analyze`.

Order lifecycle (`CustomerOrder`/`OrderStatus`): placing an order reserves stock (`Product.reservedQty` via `ProductRepository.reserveStock`) without touching `stockQty`; only advancing to `OrderStatus.delivered` deducts `stockQty` and clears the reservation; cancelling releases the reservation instead. `Product.availableStock` (`stockQty - reservedQty`) is what UI should read/limit against, not raw `stockQty`.

### Role-specific UX

Each role's home screen is tuned to what that role actually does, per `detailed_requirement.md` §2 — they are deliberately *not* the same screen with different numbers:

- **Owner** — hierarchy over completeness: a two-card "Today" hero (sales, profit), then **Needs Attention**, then Money, then Recent Activity and Staff Activity. Answers §2's "what are employees doing?". More tab: Customers, Customer Payments, Money (`CashScreen`: money in & out, expenses, owners & loans), Accounts (`AccountingScreen`), VAT books (VAT shops), Reports, Employees, Settings (My account is inside Settings), plus whatever "More features" are on.
- **Employee** ("Staff" in the UI) — a work queue, not a report: today's sales strip, a full-width **New Sale** button, then **Orders to Prepare** where each card carries its own next-step button (`nextOrderStatus`), so advancing an order never needs a detail screen. Low-stock items are listed, not counted. Staff with `reconcileCash` also get a Money section (collections, expenses, cash, receivables/payables, profit), money Needs Attention rows and recent cash-ledger rows, and their Customers tab becomes More (Customers, Money, Customer Payments, Reports, + Purchases/Suppliers when on).

Conventions to preserve when touching these:

- **More features** (Settings, owner only): `Feature` enum on `BusinessSettings.features` (settings doc field `features`, list of names; missing = off). All off by default: suppliers & purchases, categories (off: no category field, new products go in "General"), audit log, expiry tracking. Off only hides (nav, More menu, dashboards, Needs Attention, reports, product form/tiles); data and loads are untouched. Check with `settings.has(Feature.x)`.
- **`Needs Attention` only renders non-empty rows.** An empty section is a meaningful "all clear" signal — don't add always-visible zero-state rows to it.
- **Metric cards drill down.** `MetricCard.onTap` renders a chevron and makes the whole card tappable. When the destination is a *tab*, don't push a duplicate screen — use the `DashboardNav` callbacks (`lib/features/dashboard/presentation/dashboard_nav.dart`), which `AppShell` populates with the right indices for that role's tab order. Push only for non-tab destinations.
- **Quick actions are permission-filtered.** `QuickActionFab` builds its list from `auth.can(...)` and collapses to a single direct-action button when only one is permitted. It previously offered "Add Expense" to employees who lack `manageExpenses`; `business_logic_test.dart` has a regression guard for that.
- `MetricCard` is height-tolerant on purpose (fixed-height icon row, `FittedBox` value, `Flexible` two-line label) — two-word labels like "Customer Receivables" overflowed a 1.3-ratio grid cell before that. Don't "simplify" it back into a plain Column.

## Testing

`test/business_logic_test.dart` builds a real in-memory business (`TestBusiness.create()` runs first-run setup and creates one login per role; `signedIn(role)` / `business.device(role)`) and exercises controllers directly (sale cancel/return reversal, purchase stock+payable math, order reservation/finalization, permission defaults/overrides, audit logging, two-device sync, one-batch-per-operation, two-shop isolation + reset, sign-up with email verification + resume, password change/email reset, customer management, and the payment flows: door collection with split allocation, handover/shortfall, separation of duties, signature/phone confirmation, dispute/reverse, tamper detection, credit-limit flag, offline refusal + rollback, settled reversal/refund, bank/wallet accounts, cost privacy, double-entry checks after a full trading day, opening balances, year close, VAT invoices/credit notes/books, accountant export). `InMemoryRemoteStore.online` / `.rejectIf` simulate no connection / server rejection — no widget pumping, no Firebase. The in-memory store enforces **no** rules; rules are tested separately in `firestore_tests/` (`firebase emulators:exec --only firestore --project demo-sarathi "cd firestore_tests && npm test"`). Prefer adding logic tests there over widget tests; reserve `test/widget_test.dart` for things only a widget tree can verify (navigation, rendering).

## Conventions

- Currency: always format via `formatNpr()` in `lib/core/utils/formatters.dart` (Nepali/Indian digit grouping — last 3 digits, then pairs: `NPR 2,50,000`). The label is the open shop's `BusinessSettings.currency` (default NPR), copied into the global `currencyLabel` when settings load or save. Don't use `intl` for this; the grouping style isn't what `intl`'s standard formatters produce.
- Names: shops show their own `businessName` (invoices, PDFs). The product name lives only in `kAppName` (`lib/app/app.dart`).
- Ids: use `nextId('X')` from `lib/core/utils/id_generator.dart` for any new entity. It's time-ordered + random so ids from different devices don't collide, and collections are ordered by id (oldest first).
- No new dependencies beyond what's in `pubspec.yaml` (`cupertino_icons`, `flutter_lints`, `firebase_core`, `cloud_firestore`, `firebase_auth`, `firebase_crashlytics`, `pdf`, `share_plus`) without asking first — state management, navigation, and formatting are all handled with stdlib/Flutter built-ins (`ChangeNotifier`, `ListenableBuilder`, `Navigator`) on purpose.

## What NOT to do

- Do not rely on `auth.can(...)` for security. Put any new write path in `firestore.rules` (and `firestore_tests/`), or it will be rejected in production even though tests using `InMemoryRemoteStore` pass.
- Do not give delivery staff broader loads/reads than `_loadPlan` grants them.
- Do not import Firebase outside `FirestoreRemoteStore`, `FirebaseAuthRepository`, and `main.dart`.
- Do not store credentials in Firestore / `AppUser`.
- Do not add a DI framework (get_it, riverpod, etc.) to replace `AppScope` without asking.

## Agent skills

### Issue tracker

Issues live as local markdown files under `.scratch/<feature>/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: root `CONTEXT.md` + `docs/adr/`. See `docs/agents/domain.md`.
