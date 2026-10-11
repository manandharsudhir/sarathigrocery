# 'More features' toggles + menu collapse
Status: done
Blocked by: 06

Settings → More features, with on/off for: Partner capital, Suppliers+Purchases, Categories, Audit log, Expiry. All default off.
- Off hides the feature from nav, More menu, dashboards and Needs Attention. Data is not deleted.
- Merge Payments/Expenses/Accounting into one "Money" entry. Owner More menu goes to about 5 items.

## Notes

- `Feature` enum + `BusinessSettings.features` (doc field `features`: list of names, missing/unknown = off). `SettingsController.has/setFeature`; Settings screen has a "More features" switch list (owner only). Rules unchanged: settings writes are gated by `manageSettings` only, no field checks. Fixture regenerated (`features: []` on the settings write); emulator suite passes.
- Hidden when off: owner + cash-staff More menus, Owner investment tab in Money, owner dashboard "Money Payable" card + near-expiry Needs Attention row, cash-staff "Supplier Payables" card + "suppliers awaiting payment" row, Purchase/Supplier Outstanding reports, category field in product form (new products default to "General") and category prefix on inventory tiles, "Near Expiry" badge.
- Payments/Expenses/Accounting merged into one "Money" entry (screen title "Money"). My Account moved into Settings (top tile) to get the owner More menu to 6 items with everything off.
- QuickActionFab had no gated actions (Sale, Collect, Expense), so unchanged. The "Expired" stock-adjustment reason is kept.
