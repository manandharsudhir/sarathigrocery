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

Production Flutter app on Firebase (Firestore + Firebase Auth + Crashlytics), built so Firebase can be replaced by a custom backend (planned). All 10 phases of `.claude/docs/detailed_requirement.md` are implemented, plus: first-run business setup, customer add/edit + customer app logins, change password, SMS-OTP password reset.

**Accounts.** Login is phone + password through `AuthRepository`. The Firebase impl maps each phone to an email account (`<phone>@sarathigrocery.app`). The account id (Firebase uid) is the `AppUser` document id, and credentials never touch Firestore. First run: "Set up a new business" on the login screen (`SetUpBusiness`) creates the owner and `meta/setup` atomically, and the rules accept this exactly once. After that, the owner creates staff (Employees) and customer logins (Customer detail). Minimum password length is 8 (`passwordProblem`).

**Password reset.** A user verifies their phone once (Account screen, or the banner in `AppShell`), which links a Firebase phone credential to their login. After that, "Forgot password" sends an OTP, and the OTP sign-in lands in the same account, which then sets a new password. OTP reset is refused for unverified phones (their phone-only account is deleted immediately). Phones are local numbers; `FirebaseAuthRepository._countryCode` is `+977`.

**Enforcement.** `firestore.rules` enforces roles/permissions server-side and mirrors `Permission` defaults plus per-user overrides. Staff read the whole business; every write needs the permission the UI checks. Customers read the catalogue plus their own profile/account/orders/notifications, and can only place orders. Ledgers and the audit log are append-only. The UI's `auth.can(...)` checks are UX only; the rules are the real gate. Tests: `firestore_tests/` (21 cases, emulator).

**Monitoring.** `reportError` (`lib/core/services/error_reporter.dart`) is set to Crashlytics in `main.dart` (not on web). Uncaught Flutter/platform errors are recorded as fatal. Collection is off in debug builds.

## Backend seam

Two interfaces are the entire backend contract. Only `FirestoreRemoteStore`, `FirebaseAuthRepository`, `main.dart` and `firestore.rules` know about Firebase:

- `RemoteStore` (`lib/core/data/remote_store.dart`): `watch(collection, {id, where})`, `get`, and `commit(List<WriteOp>)` (atomic). Impls: `FirestoreRemoteStore`, `InMemoryRemoteStore` (tests). On a custom backend these map to GET/stream, GET by id, and `POST /commit`. The server must then enforce what `firestore.rules` does today.
- `AuthRepository` (`lib/features/auth/domain/repositories/auth_repository.dart`): sign in/out, create account, change password, phone verification, OTP reset. Impls: `FirebaseAuthRepository`, `InMemoryAuthRepository` (tests; `lastOtp` exposes the fake code).

`main.dart` passes the Firebase pair into `AppScope(store:, authRepository:)`, and `AppScope()` with no args is fully in-memory.

Repositories stay **synchronous** on top of `SyncedCollection<T>` (`lib/core/data/synced_collection.dart`). It holds a local mirror of one collection, loaded at login per role (`AppScope._loadPlan`) and kept live by `watch`. Writes go through the shared `WriteQueue` (`lib/core/data/write_queue.dart`), which batches every write made in one event-loop turn into one atomic commit. Since use cases are synchronous, each operation (e.g. `RecordSale`) is all-or-nothing on the server without the domain layer knowing. JSON mapping lives next to each repo impl (`toJson`/`fromJson`/`merge`). Rules when touching data:

- Every mutation of a persisted entity must go through its repository (`add`/`save`/`increment`). A direct field mutation changes only this device.
- Don't `await` inside a use case between writes that must be atomic. An `await` splits the batch.
- `_loadPlan` and `firestore.rules` must agree. A watch the rules reject fails that role's login. `firestore_tests` has an "app load plan" test mirroring `_loadPlan`: update both together.
- `save()` writes all non-counter fields, and rules compare *changed* keys. Documents must therefore contain every field `toJson` writes (see the defaults in `sample_data.dart`), or a later save looks like it adds fields and staff-only-field rules reject it.
- Remote snapshots are merged **in place** (entities reference each other by object). New mutable fields need adding to `merge`.
- Concurrently changed numbers (stock, reserved qty, customer balance, supplier payable) use `increment` and are listed in `counters`.
- Cross-references are stored as ids and resolved via `byId` in `fromJson`. Unresolved docs are retried automatically.
- The cart is device-local. Logout detaches and clears every mirror.

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
│   ├── utils/formatters.dart      formatNpr (Nepali digit grouping), formatDate, formatDaysAgo
│   ├── services/app_signal.dart   see "Cross-feature reactivity" below
│   └── widgets/            MetricCard, StatusBadge — used by 3+ features
└── features/
    ├── auth/               UserRole, Permission, AppUser, login, AuthController
    ├── inventory/          Product, categories, stock adjustments
    ├── customers/          Customer, credit status, payment recording
    ├── suppliers/          Supplier, payable
    ├── purchasing/         Purchase, receiving stock, purchase returns
    ├── sales/              Sale, record/cancel/return, invoices
    ├── cash/               cash ledger, expenses, partner capital
    ├── ordering/           cart, CustomerOrder, order lifecycle
    ├── employees/          employee accounts + permission editing (uses auth's UserRepository)
    ├── settings/           business settings
    ├── notifications/      presentation-only consumer of NotificationRepository (no controller — see below)
    ├── audit/              presentation-only consumer of AuditRepository (no controller)
    ├── reports/            presentation-only: 13 report views reading other features' controllers directly
    └── dashboard/          presentation-only: 4 role dashboards composing 5-6 controllers each
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

- **Owner** — hierarchy over completeness: a two-card "Today" hero (sales, profit), then **Needs Attention**, then Money, then Recent Activity and Staff Activity. Answers §2's "what are employees doing?".
- **Accountant** — money-first: today's sales/collections/expenses/cash, overdue customers and unpaid suppliers, balances, then a recent-transactions feed read straight off the cash ledger.
- **Employee** — a work queue, not a report: today's sales strip, a full-width **New Sale** button, then **Orders to Prepare** where each card carries its own next-step button (`nextOrderStatus`), so advancing an order never needs a detail screen. Low-stock items are listed, not counted.
- **Customer** — shopping-shaped: credit headroom in plain language ("NPR X still available of your NPR Y limit"), Browse Products, one-tap "Reorder last", live order progress bars, cart badge on the nav.

Conventions to preserve when touching these:

- **`Needs Attention` only renders non-empty rows.** An empty section is a meaningful "all clear" signal — don't add always-visible zero-state rows to it.
- **Metric cards drill down.** `MetricCard.onTap` renders a chevron and makes the whole card tappable. When the destination is a *tab*, don't push a duplicate screen — use the `DashboardNav` callbacks (`lib/features/dashboard/presentation/dashboard_nav.dart`), which `AppShell` populates with the right indices for that role's tab order. Push only for non-tab destinations.
- **Quick actions are permission-filtered.** `QuickActionFab` builds its list from `auth.can(...)` and collapses to a single direct-action button when only one is permitted. It previously offered "Add Expense" to employees who lack `manageExpenses`; `business_logic_test.dart` has a regression guard for that.
- `MetricCard` is height-tolerant on purpose (fixed-height icon row, `FittedBox` value, `Flexible` two-line label) — two-word labels like "Customer Receivables" overflowed a 1.3-ratio grid cell before that. Don't "simplify" it back into a plain Column.

## Testing

`test/business_logic_test.dart` builds a real in-memory business (`TestBusiness.create()` runs first-run setup and creates one login per role; `signedIn(role)` / `business.device(role)`) and exercises controllers directly (sale cancel/return reversal, purchase stock+payable math, order reservation/finalization, permission defaults/overrides, audit logging, two-device sync, one-batch-per-operation, customer data scoping, setup-once, password change/OTP reset, customer management) — no widget pumping, no Firebase. The in-memory store enforces **no** rules; rules are tested separately in `firestore_tests/` (`firebase emulators:exec --only firestore --project demo-sarathi "cd firestore_tests && npm test"`). Prefer adding logic tests there over widget tests; reserve `test/widget_test.dart` for things only a widget tree can verify (navigation, rendering).

## Conventions

- Currency: NPR, formatted via `formatNpr()` in `lib/core/utils/formatters.dart` (Nepali/Indian digit grouping — last 3 digits, then pairs: `NPR 2,50,000`). Don't use `intl` for this; the grouping style isn't what `intl`'s standard formatters produce.
- Ids: use `nextId('X')` from `lib/core/utils/id_generator.dart` for any new entity. It's time-ordered + random so ids from different devices don't collide, and collections are ordered by id (oldest first).
- No new dependencies beyond what's in `pubspec.yaml` (`cupertino_icons`, `flutter_lints`, `firebase_core`, `cloud_firestore`, `firebase_auth`, `firebase_crashlytics`) without asking first — state management, navigation, and formatting are all handled with stdlib/Flutter built-ins (`ChangeNotifier`, `ListenableBuilder`, `Navigator`) on purpose.

## What NOT to do

- Do not rely on `auth.can(...)` for security. Put any new write path in `firestore.rules` (and `firestore_tests/`), or it will be rejected in production even though tests using `InMemoryRemoteStore` pass.
- Do not give customers broader loads/reads. They currently see product `purchasePrice` (cost) through the catalogue, a known gap. The fix is a staff-only `productCosts` collection.
- Do not import Firebase outside `FirestoreRemoteStore`, `FirebaseAuthRepository`, and `main.dart`.
- Do not store credentials in Firestore / `AppUser`.
- Do not add a DI framework (get_it, riverpod, etc.) to replace `AppScope` without asking.
