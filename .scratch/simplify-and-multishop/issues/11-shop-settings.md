# Per-shop name, currency, country code
Status: done
Blocked by: 08

The shop settings doc holds name, currency (default NPR) and country code (default +977).
- `formatNpr` reads the currency.
- `FirebaseAuthRepository._countryCode` reads the country code.
- Invoice, login and app title use the shop name or the neutral brand. Fixes the hardcoded "Sarathi Grocery" in invoice_screen.dart.

## Notes

- `BusinessSettings` gained `currency` ('NPR') and `countryCode` ('+977'); missing doc fields read as those defaults. Sign-up writes them via the entity defaults. Settings screen: two plain text fields (blank = keep current). `SettingsController.update` takes them as optional params.
- `formatNpr` uses a top-level `currencyLabel` (formatters.dart), set by the settings repo whenever the doc is loaded/merged/saved. Process-global, marked `ponytail:`. PDFs pick it up for free (they call `formatNpr`).
- Country code: auth (`FirebaseAuthRepository._countryCode`) stays '+977' app-wide, because login/sign-up/OTP reset run before any shop is open. The shop setting is stored and editable but nothing reads it yet: no shop-context phone formatting/WhatsApp links exist. Use it when one is added.
- Invoice header reads the shop name (`SalesController.businessName`, same closure pattern as payments/ordering). The "Wholesale Grocery & FMCG" subtitle was dropped. App title + login use `kAppName = 'Sarathi'` (lib/app/app.dart, one place; change once Q26 decides). Login subtitle: "Shop management". Settings fallback defaults (before the doc loads) are now empty instead of a fake shop.
- Rules unchanged (settings writes are gated by `manageSettings`, no field checks). Fixture regenerated (settings writes now carry `currency`/`countryCode`); emulator suite 44 pass. business_logic: new shop-settings test (defaults, invoice name, currency label, sync to staff).
