# Spec: Simpler app + self-serve multi-shop (Play Store)

Status: ready-for-agent

## Goal

A simpler app that shop staff use. Any shop in Nepal can install it from the Play Store and set itself up.

## Decisions

- **Roles:** owner, staff, delivery. Accountant becomes a staff toggle: "Can handle cash & accounts" (`reconcileCash` + money permissions).
- **No customer logins.** Customers are records the shop keeps (credit, statement). The statement PDF is shared via WhatsApp. Removed: customer screens, delivery codes (`deliveryCodes`, `codeChecks`), customer read rules, the customer branch of `_loadPlan`.
- **Core features:** Sales, Stock, Customers (udharo), Orders, Money (one screen; replaces Payments/Expenses/Accounting).
- **Advanced features**, off by default and toggled in Settings → "More features": Partner capital, Suppliers + Purchases, Categories, Audit log, Expiry. Hiding only, data is never deleted. Owner More menu goes from 13 items to about 5.
- **UX:**
  - Product search and searchable customer/supplier pickers on new sale, new purchase and new order.
  - Every empty state gets an action button.
  - Orders get a single "Next" button. All statuses are kept.
- **Wording:** see the glossary below. "Udharo" stays. Nepali localization is out of scope.
- **Safeguards** are per-shop toggles, off by default: signature at the door, phone confirmation of unsigned payments, cash handover + "cash missing" tracking, online-only collection. The app offers to switch them on when the first staff account is created. The rules enforce whatever is on.
- **Multi-shop:**
  - One shared Firebase project. All shop data lives under `shops/{shopId}/...`.
  - One login per phone. Membership docs give `{shopId, role, permissions}`. The shop picker appears only for users with more than one membership.
  - Owner sign-up: phone, SMS OTP, then password.
  - Reset and delete act on one shop's subtree only.
  - Shop settings hold name, currency (NPR) and country code (+977). Invoices read the shop name from settings.
- **Account deletion:** staff and delivery accounts are anonymised (login and profile deleted, the shop's records kept). Owner deleting the shop: export first, confirm twice, delete immediately (no grace period, decided 2026-10-03).
- **Product:** one app with a neutral brand name. Free, no billing code. Start from fresh data, no migration.

## Glossary (UI wording)

| Current | New |
|---|---|
| Udharo | keep |
| Settle / Receive / counted into till | Count cash in |
| Shortfall / Short by | Cash missing |
| In till / not yet in the till | With shop / With staff |
| Daily Ledger | Money in & out |
| Partner Capital | Owner investment |
| Opening balance | Old udharo (before app) |
| Reverse payment | Undo payment |
| unexplained difference | Balance doesn't add up, check records |

## Order

1. UX baseline
2. Remove customer logins, collapse roles, feature toggles
3. Multi-shop
4. Safeguard toggles
5. Play Store

## Open

- Q26: who publishes (personal or Insyde AI)? It decides the Play Console account, applicationId, privacy policy entity and support email. It blocks ticket 14 only.

## Before release

- Legal/compliance review of: privacy policy, deletion/retention policy (Nepal rules for financial records), Data Safety form, payment/balance wording.
- Insyde sign-off if this is an Insyde product.
