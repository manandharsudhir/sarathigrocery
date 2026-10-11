# Owner sign-up with SMS OTP
Status: done
Blocked by: 09

Set up a new shop: phone, SMS OTP, then password, then shop name. This creates the shop and the owner membership atomically.

Reuse the existing phone verification/OTP code. Remove the always-visible setup button behaviour from single-tenant days.

## Notes

- Flow (`SetupScreen`, opened by "New shop? Sign up" on login): phone → SMS code → password + confirm (new logins only) → shop name + owner name → owner dashboard. The old phone+password setup path is gone; `SetUpBusiness` now works only for the signed-in login and refuses one without a verified phone.
- `AuthRepository` gained `signInWithCode` (OTP sign-in; true = landed in an existing verified login) and `addPassword` (Firebase: `linkWithCredential(EmailAuthProvider…)` on the phone-only login, then a token refresh, so the account has email + phone and OTP reset works at once). OTP send reuses `startPasswordReset`. In-memory OTPs now survive a wrong code, as Firebase verification ids do.
- Existing login: verified phone → OTP signs into it, password step skipped, password unchanged, new shop added. Never verified → link fails (`email-already-in-use`), the new phone-only login is deleted (as OTP reset does) and `kUnverifiedSignUpMessage` tells them to log in, verify under Account, then Account → "Set up another shop" (new owner-only entry; opens the verify dialog when unverified). An abandoned sign-up leaves a phone-only login; a later sign-up with that phone reuses it, OTP reset deletes it.
- Rules: shop creation (`creatingShop` + `shops/{id}` create) requires `request.auth.token.phone_number`. Fixture records `actorPhoneVerified`; replay adds the claim. firestore_tests 43 cases + replay (new: unverified login can't create a shop).
- Tests: business_logic 40 (new: OTP sign-up incl. wrong code/short password/immediate OTP reset; existing verified vs unverified login). Widget first-run test drives the 4 steps incl. a wrong code. Shared helper `test/sign_up.dart`.
- Firebase console setup (human): enable the Phone sign-in provider; add the release + debug (and Play App Signing) SHA-1 and SHA-256 fingerprints to the Android app and re-download `google-services.json`; enable the Play Integrity API in the Google Cloud project (reCAPTCHA fallback otherwise); allow SMS region Nepal (+977) under Authentication → Settings → SMS region policy; add test phone numbers + fixed codes for development/Play review; check SMS quota/billing (Blaze plan). Web needs the domain in Authorized domains.
