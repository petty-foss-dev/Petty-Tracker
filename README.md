<p align="center">
  <img src="EnveKeep/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="88" alt="Enve Keep app icon">
</p>

<h1 align="center">Enve Keep for iOS</h1>

<p align="center"><strong>Your receipts, warranties, subscriptions, and important dates. In one place.</strong></p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0--only-2F6F62" alt="License: AGPL-3.0-only"></a>
  <img src="https://img.shields.io/badge/iOS-17%2B-222222?logo=apple" alt="Requires iOS 17 or later">
  <img src="https://img.shields.io/badge/built_with-SwiftUI-F05138?logo=swift&logoColor=white" alt="Built with SwiftUI">
  <a href="https://buymeacoffee.com/envebookplayer"><img src="https://img.shields.io/badge/Buy_Me_a_Coffee-support_the_project-FFDD00?logo=buymeacoffee&logoColor=000000" alt="Support on Buy Me a Coffee"></a>
</p>

Enve Keep is a free, open source iPhone app that helps you keep the paperwork behind everyday purchases organized. Scan a receipt, find it later by merchant or trip, and keep proof of purchase beside the product it belongs to. Get reminders before a warranty ends, a subscription renews, or a document expires.

Records and receipt recognition stay on your iPhone. No account, ads, analytics, subscriptions, or paid feature tiers.

**[Build the app](#build-and-run)** · **[Feature reference](docs/REFERENCE.md)** · **[Report a bug](https://github.com/opisaac9001/Enve-Keep-iOS/issues/new/choose)** · **[Android companion](https://github.com/opisaac9001/Enve-Keep-Android)**

## A look inside

Real screenshots from the iPhone Air simulator, using fictional demo records.

<table>
  <tr>
    <th>Stay ahead of important dates</th>
    <th>Keep receipts together</th>
  </tr>
  <tr>
    <td><img src="docs/screenshots/home.png" width="300" alt="Dashboard with upcoming renewals, a warranty deadline, and a document expiry"></td>
    <td><img src="docs/screenshots/receipts.png" width="300" alt="Receipt library with categories, trip routes, tags, and monthly totals"></td>
  </tr>
  <tr>
    <th>Browse by what matters to you</th>
    <th>Find the receipts for a trip</th>
  </tr>
  <tr>
    <td><img src="docs/screenshots/browse.png" width="300" alt="Receipt categories and browse options for routes, merchants, locations, tags, and custom fields"></td>
    <td><img src="docs/screenshots/trip.png" width="300" alt="Three receipts filtered to the San Francisco to Los Angeles trip, with a combined total"></td>
  </tr>
</table>

[View a receipt's store, payment, trip, and fuel details](docs/screenshots/details.png).

## What you can do

| Area | Features |
| --- | --- |
| **Scan receipts** | Document camera, Photos, Files, and PDF import. Apple Vision recognizes text on the device. Keep the original pages and edit the extracted details. |
| **Itemize purchases** | Merchant, date and time, items and quantities, discounts, subtotal, tax, tip, and total. Read printed store, transaction, payment, and fuel details when the text clearly supports them. |
| **Find and organize** | Categories, tags, store locations, trip endpoints, and any number of custom fields. Search the fields and original OCR text, combine filters, and see totals in each currency. |
| **Review scans** | Find missing fields, unreadable pages, inconsistent totals, identical scans, and possible duplicates in the review inbox. |
| **Keep warranties** | Product details, serial numbers, warranty dates, attachments, and linked receipts. Create a product from a receipt item and export a warranty claim PDF. |
| **Track recurring costs** | Flexible subscription cycles, renewal dates, cancellation, and local reminders. |
| **Remember document dates** | Issuer, reference number, issue and expiry dates, notes, and attachments. |
| **Capture and export** | Share images and PDFs into Enve Keep, use the Scan Receipt App Intent, export the current receipt results as CSV, or back up records and attachments to a ZIP. |

For example, open **Receipts → Browse → Fuel**, narrow by a route, then add **Vehicle = Civic** or a date range. Export just those matching receipts for a trip or reimbursement.

OCR can make mistakes, especially with handwriting. Every extracted field is editable; missing details stay blank. Trip endpoints and custom fields are entered by you. The document camera requires a physical iPhone. PDF imports support up to 20 pages per file, and the share extension accepts up to 20 files at a time.

## Privacy and backups

The app makes no network requests. Your records and attachments live in local storage; Apple Vision processes receipt images on the device. Shared files wait in the app's local shared inbox until you save or discard them.

**Export backups regularly.** Records and attachments are excluded from automatic iCloud device backups. You choose when to share a receipt, CSV, claim PDF, or ZIP backup.

Backups without receipts use the Android-compatible version 1 format. Receipt backups use version 3 and can be restored by current iOS builds. Existing version 2 iOS backups still import. Android does not currently support receipts and rejects receipt backups. See the [backup reference](docs/REFERENCE.md#backup-format) for details.

## Build and run

The source is available now. There is currently no packaged iOS release in this repository; build it with Xcode to try it.

You need a Mac with **Xcode 26 or later** and **[XcodeGen](https://github.com/yonaskolb/XcodeGen)**. The deployment target is **iOS 17.0**. Swift Package Manager resolves the pinned ZIPFoundation dependency.

```sh
git clone https://github.com/opisaac9001/Enve-Keep-iOS.git
cd Enve-Keep-iOS
xcodegen generate
open EnveKeep.xcodeproj
```

Choose the **EnveKeep** scheme and an iPhone simulator, then run. Simulator receipt capture supports Photos, Files, and manual entry.

To build and test from Terminal with an installed iPhone Air simulator:

```sh
xcodebuild -project EnveKeep.xcodeproj -scheme EnveKeep \
  -destination 'platform=iOS Simulator,name=iPhone Air' \
  CODE_SIGNING_ALLOWED=NO build test
```

For a physical iPhone, select your development team for both **EnveKeep** and **EnveKeepShare**. The targets use `com.enve.keep`, `com.enve.keep.share`, and the shared App Group `group.com.enve.keep`. Your signing setup must support these identifiers. If you use your own identifiers, update both targets and entitlements in `project.yml`, and the App Group value in `Shared/SharedInbox.swift`, then regenerate the project.

The latest feature verification passed **135 tests on iOS 17 and iOS 27 simulators**, with no build warnings. Route and custom field browsing, CSV sharing, claim PDF preview, and the Photos share extension were exercised in Simulator. Camera capture, handwriting on real receipts, and Shortcut discovery still need physical iPhone verification.

## Contribute

Bug reports, accessibility improvements, documentation, and focused pull requests are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md). Please use fictional or redacted receipts in issues and screenshots.

The [feature and backup reference](docs/REFERENCE.md) explains the data format and project layout. This repository contains the iOS app; the [Android companion](https://github.com/opisaac9001/Enve-Keep-Android) has its own repository.

## Support the project

Enve Keep is free. If you'd like to help fund development, you can [buy me a coffee](https://buymeacoffee.com/envebookplayer). Support is optional and doesn't unlock features. Reporting a useful bug or contributing a fix helps too.

<a href="https://buymeacoffee.com/envebookplayer"><img src="https://img.shields.io/badge/Buy_Me_a_Coffee-support_Enve-FFDD00?style=for-the-badge&logo=buymeacoffee&logoColor=000000" alt="Buy Me a Coffee"></a>

## License

Enve Keep's original source is licensed under the **GNU Affero General Public License v3.0 only** (`AGPL-3.0-only`), matching Enve Book Player. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).

Third-party components retain their own licenses. ZIPFoundation is MIT licensed; its attribution and license are retained in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
