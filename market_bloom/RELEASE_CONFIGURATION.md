# PoMarket Android and iOS release configuration

Audit date: August 14, 2026.

This file contains no credentials. Populate protected values in the release environment and never commit secrets, keystores, service-account files, receipts, API tokens, or production backend credentials.

## Repository release safeguards

The repository now enforces these safety rules:

- Android release tasks fail when signing values are absent, placeholders remain, the keystore path is invalid, or the AdMob App ID is missing/test-only.
- Android relative keystore paths are resolved from the `android` project directory.
- Mobile release runtime startup rejects missing/non-HTTPS privacy, Cloud Save, and purchase-verification URLs.
- Mobile release runtime startup rejects missing platform ad-unit IDs.
- Store purchases are unavailable when the dedicated purchase-verification endpoint is not configured; the client no longer reuses the Cloud Save endpoint for purchase verification.
- Protected Firebase files and the populated iOS release xcconfig are gitignored.

These safeguards do not replace signed archive/AAB testing or store-console configuration.

## Application identity and version

- Android application ID: `com.sergiopodolyak.pomarket`
- Android namespace: `com.sergiopodolyak.pomarket`
- iOS bundle ID: `com.sergiopodolyak.pomarket`
- Display name: `PoMarket`
- Flutter version source: `pubspec.yaml` (`version: 1.0.0+1`)
- Minimum Android API: 24
- Minimum iOS version: 13.0
- Orientation: portrait

Increase the build number for every Google Play or App Store upload. Confirm both store records use the identifiers above before the first submission; changing an identifier after release creates a different app.

Google Play requires new apps and updates to target Android 16/API 36 starting August 31, 2026. The project uses Flutter's configured `compileSdk` and `targetSdk`; verify the actual merged manifest/AAB target before submission and update the installed Flutter/Android SDK if it is below API 36.

Apple has required App Store Connect uploads to be built with Xcode 26 and the iOS 26 SDK or later since April 28, 2026. Archive with a compliant Xcode installation.

## Android release signing

1. Copy `android/key.properties.example` to `android/key.properties`.
2. Populate the release keystore path, alias, and passwords.
3. Keep `android/key.properties` and the keystore outside source control and back them up securely.
4. Preserve the upload key and Play App Signing recovery information.

Release tasks intentionally fail instead of silently producing a debug-signed release.

## iOS signing

Open `ios/Runner.xcworkspace` in Xcode and configure:

- Apple Developer team
- Automatic or managed distribution signing
- App Store distribution profile
- Bundle ID `com.sergiopodolyak.pomarket`

No Apple team ID, certificate, or provisioning profile is stored in this repository.

## AdMob and ads privacy

### Android native App ID

Provide `POMARKET_ADMOB_APP_ID_ANDROID` as either a Gradle property or environment variable when creating a release build. Debug builds use Google's official sample App ID.

### iOS native App ID

Copy `ios/Flutter/ReleaseSecrets.xcconfig.example` to `ios/Flutter/ReleaseSecrets.xcconfig` and populate `POMARKET_ADMOB_APP_ID`, or inject that Xcode build setting in CI. Debug builds use Google's official sample App ID.

### Dart ad-unit IDs

Supply these with `--dart-define`:

- `ADMOB_REWARDED_ANDROID`
- `ADMOB_REWARDED_IOS`
- `ADMOB_INTERSTITIAL_ANDROID`
- `ADMOB_INTERSTITIAL_IOS`

Do not ship Google's test ad-unit IDs in a store build.

### Remaining ads blocker

The game has its own optional-ads privacy switch, but Google UMP consent-form/privacy-options flow is not integrated in Dart. Before distributing ads in regions where Google requires consent, either integrate and device-test UMP or restrict release/ads availability to a legally reviewed configuration. AdMob Privacy & messaging console setup is also required.

## In-app purchase products

Create matching products in Google Play Console and App Store Connect:

- `pomarket_no_ads` — non-consumable
- `pomarket_coin_pack` — consumable
- `pomarket_gem_pack` — consumable
- `pomarket_emergency_supply` — consumable
- `pomarket_starter_pack` — non-consumable

Configure pricing, tax, availability, review metadata, tester accounts, and translations in each store. Product IDs and product types must match exactly. Test purchase, cancellation, pending payment, restore, refund/revocation behavior, and repeat delivery.

## Server-side purchase verification

Supply a dedicated absolute HTTPS endpoint with:

- `POMARKET_PURCHASE_VERIFICATION_ENDPOINT`

The client calls `POST {endpoint}/v1/purchases/verify`. The server must validate Google Play and App Store transactions with the relevant store, bind each transaction to the expected account and product, enforce idempotency, reject replay/cross-account delivery, and return the response contract expected by `purchase_verification_service.dart`.

Store purchase UI remains unavailable when this endpoint is absent.

## Cloud Save

Supply an absolute HTTPS endpoint with:

- `POMARKET_CLOUD_SAVE_ENDPOINT`

Validate upload, download, conflict resolution, recovery codes, deletion, offline retry, account-secret handling, rate limits, authorization, and backend backup/restore against production. The current client uses a generated account ID, device ID, and sync secret; the backend must treat the sync secret as a credential.

## Analytics

If production analytics is enabled, supply:

- `POMARKET_ANALYTICS_ENDPOINT`

If omitted, analytics remains disabled even when a player enables the in-game analytics choice. Confirm retention, deletion, access control, event schema, and privacy disclosures.

## Firebase and Crashlytics

Run `flutterfire configure` for the final Android and iOS app records and add protected production configuration through the release process:

- Android `google-services.json` and Google Services/Crashlytics Gradle integration
- iOS `GoogleService-Info.plist` with Runner target membership
- Generated `firebase_options.dart` if required by the selected FlutterFire setup
- Android mapping/native symbol upload as applicable
- iOS dSYM upload build phase and symbolication verification

The repository contains the consent-gated Crashlytics client but not Firebase project configuration or symbol-upload wiring. Test opt-in, revocation, non-fatal reporting, fatal reporting, and symbolication on real release builds.

## Privacy

Supply a public absolute HTTPS privacy-policy URL with:

- `POMARKET_PRIVACY_POLICY_URL`

Complete outside the repository:

- Google Play Data safety form
- App Store privacy details
- AdMob UMP/privacy-message configuration
- Apple privacy-manifest and required-reason API archive review
- ATT determination if advertising configuration tracks users across apps/sites
- Support and data-deletion contact/process
- Legal review for analytics, crash reporting, ads, Cloud Save, and purchase records

The in-game privacy choices do not replace platform consent flows, store disclosures, or legal review.

## Example release defines

Use protected CI variables rather than committing values:

```text
--dart-define=POMARKET_PRIVACY_POLICY_URL=https://...
--dart-define=POMARKET_CLOUD_SAVE_ENDPOINT=https://...
--dart-define=POMARKET_PURCHASE_VERIFICATION_ENDPOINT=https://...
--dart-define=POMARKET_ANALYTICS_ENDPOINT=https://...
--dart-define=ADMOB_REWARDED_ANDROID=...
--dart-define=ADMOB_REWARDED_IOS=...
--dart-define=ADMOB_INTERSTITIAL_ANDROID=...
--dart-define=ADMOB_INTERSTITIAL_IOS=...
```

## Platform assets and launch configuration

Present in the repository:

- Android launcher/adaptive icon resources
- Android launch themes including Android 12 splash resources
- iOS AppIcon asset catalog
- iOS launch storyboard and launch image/background assets
- Portrait orientation configuration

Validate all required icon slots, transparency, safe-area rendering, launch appearance, and store marketing artwork in final archives and on physical devices.

## Required Android checks

- Build a signed release AAB with the production release environment.
- Confirm target API 36 in the generated artifact before August 31, 2026 submission requirements apply.
- Install through a Play internal/closed track.
- Test all Billing products and restore behavior with license testers.
- Verify purchases deliver exactly once after server verification.
- Validate AdMob with registered test devices before enabling production ads.
- Validate Firebase/Crashlytics collection consent and symbolication.
- Validate Cloud Save online/offline/recovery/deletion behavior.
- Test phone/tablet safe areas, back navigation, lifecycle save, process death, offline startup, and upgrade install.

## Required iOS checks

- Archive with Xcode 26/iOS 26 SDK or later.
- Validate and upload to TestFlight.
- Test all StoreKit sandbox products and restore behavior.
- Verify purchases deliver exactly once after server verification.
- Validate AdMob with test-device configuration before production ads.
- Validate Firebase/Crashlytics collection consent and dSYM symbolication.
- Inspect the archive privacy report and bundled third-party privacy manifests.
- Validate Cloud Save online/offline/recovery/deletion behavior.
- Test notch, Dynamic Island, home indicator, lifecycle save, process termination, offline startup, and upgrade install.

## Store submission work outside this repository

- Store listings, screenshots, descriptions, categories, age/content ratings, support URL, and marketing artwork
- Privacy policy hosting and data-safety/privacy questionnaires
- In-app purchase review metadata and screenshots
- App-review notes and demo/test credentials where required
- Pricing, countries, tax, banking, and paid-app agreements
- Export-compliance answers
- Internal/closed testing, TestFlight review, staged rollout, monitoring, and rollback plan
