# Feature and backup reference

A free, open source iPhone app for keeping track of product warranties, subscriptions, document expiry dates and receipts. Everything stays on your phone. The native apps live in [ios/](../ios/) and [android/](../android/). Backups without receipts work across both apps; receipts use a newer iOS backup format.

## Features

- **Dashboard**: past-due items (expired documents, missed renewals, warranties that ended in the last month), everything coming up within your reminder windows, a per-category overview and estimated monthly spend. Search covers every record.
- **Warranties**: products with brand, model, serial number, purchase date, retailer, price and currency, warranty end date (with 1/2/3/5-year shortcuts), notes and any number of receipts, photos or PDFs. Share a product's details as text when making a claim.
- **Subscriptions**: price, currency, a billing cycle of every N days/weeks/months/years, and the next renewal. Renewals follow the original billing date, so a plan billed on the 31st renews on the last day of shorter months and returns to the 31st afterwards. You can mark a renewal as paid, mark a subscription as canceled, or reactivate it.
- **Documents**: passports, licences, insurance and similar, with issuer, document number, issue and expiry dates, notes and attachments.
- **Receipts**: scan paper receipts with the document camera (edges are found, cropped and straightened, and long receipts can span several pages), pick images from Photos, pick images or PDFs from Files, or enter a receipt by hand. Each PDF page (up to 20 per file) is stored as a JPEG page so it can be read like a scan; password-protected, damaged or longer PDFs are refused with a message. Apple's Vision framework reads the text on the iPhone, and Enve Keep drafts the merchant, purchase date and time, currency, line items with quantities, discounts, subtotal, tax, tip and total for you to check. It also picks up printed details: the store address and phone number, the receipt or transaction number, the payment method and the card's last four digits when the receipt shows them masked (such as `****1234`), and an odometer reading. On fuel receipts it reads the grade, the volume in gallons or liters, the price per unit and the pump number, and files the receipt under Fuel. It only does this when the evidence is strong, such as a volume next to a pump number or a price per gallon; a bottle size or the word "diesel" on its own isn't enough. Recognition can make mistakes, especially with handwriting, so every field stays editable and anything the text doesn't clearly state is left blank rather than guessed. Each receipt keeps its page images and the original recognized text, and that text stays searchable even where no field was filled in.
- **Organizing receipts**: add where a trip started and ended (From and To, which you always enter yourself; they are never guessed from the store address), and any number of custom fields with your own names and values, such as Vehicle, Project or Trip purpose. The list can be searched across every field, custom field names and values and the scanned text, sorted by date, total (highest or lowest), merchant, store location or trip route, grouped by month, category or merchant with per-currency totals, and filtered by category or tag. **Browse** shows every category, route, merchant, store location, tag and custom field with how many receipts each has and their totals per currency. Tap one to see its receipts, then narrow them further by another of those, by part of a place name ("San Fran" to "Los"), a date range, a total range or a currency, and sort or export exactly what is shown. So a route like San Francisco → Los Angeles is a few taps away, even among hundreds of fuel receipts. Tapping a receipt's route, store address or custom field opens the other receipts that share it. Share a receipt's details as text or its original scans. The document camera needs a real iPhone; in Simulator, receipts can be added from Photos, Files or by hand.
- **CSV export**: export all receipts, or exactly the ones shown after searching and filtering, as a UTF-8 CSV with one row per line item. Columns cover the receipt's date and time, store details, payment, trip, fuel details, items, totals and original recognized text, followed by one `Custom: <name>` column for each custom field name (a name used twice on one receipt gets a second column). Amounts are plain decimals, dates ISO `yyyy-MM-dd` and times `HH:mm`, and text that a spreadsheet could mistake for a formula is prefixed with an apostrophe.
- **Save to Enve Keep**: share images or PDFs from Photos, Files or any other app with the "Save to Enve Keep" share extension, up to 20 at a time. The files are copied into Enve Keep's shared inbox on the device before the share sheet closes; if they can't be copied, the share sheet says so and nothing is saved. Items that aren't images or PDFs are skipped and counted. The next time Enve Keep opens or comes to the front, it switches to Receipts and opens each shared file as a new receipt draft, one after another, so you can check the recognized details before saving. Canceling a draft asks whether to review it later or delete the shared file; files kept for later wait under "shared files to review" at the top of Receipts and open again on the next launch. A shared file is removed from the inbox only after its receipt is saved or you delete it. If something else is open in the app, such as an editor, Enve Keep waits instead of interrupting it.
- **Shortcuts and Siri**: the "Scan Receipt" action (or "Scan receipt in Enve Keep") opens the app on Receipts with the document camera ready. Where the camera scanner isn't available, such as in Simulator, it offers Photo Library, Files or manual entry instead. A request that hasn't been handled within 10 minutes is dropped.
- **Attachments**: add files from the Files app, pick from your photo library, or take a photo. Everything is copied into the app's private storage, and photos are saved as JPEG so they open on any device. Tap an attachment to preview it with Quick Look, or share it with its original name.
- **Reminders**: local notifications at 9 AM when a date enters its reminder window and again when it arrives. Lead times are configurable per category, and the app asks for notification permission in context.
- **Backup**: export every record, receipt, attachment and setting to a single ZIP file, then import it on this or another device. Backups without receipts also import into Enve Keep for Android (see below). Imports are fully validated in a staging area first. Unexpected entries, path traversal, symlinks, bad checksums, oversized archives and dangling attachment references are all rejected, and your existing data is replaced only after you confirm.
- System, light and dark themes, plus VoiceOver labels throughout.

## Privacy

Enve Keep has no accounts, servers, analytics, ads or in-app purchases, and it makes no network requests. Records and files live only in the app's private storage and are excluded from iCloud device backups. Receipt text is recognized on the device with Apple's Vision framework; no image or text is sent anywhere. Files shared to Enve Keep wait in an App Group container that only Enve Keep and its share extension can read, protected until the device is first unlocked and excluded from iCloud device backups. The only way data leaves the app is when you export a backup or share a file yourself.

## Backup format

The ZIP holds `backup.json` and a flat `attachments/` folder. The manifest uses the same keys and types as Android: ISO `yyyy-MM-dd` dates, decimal amounts as strings, upper-case enum names and explicit `null`s. For the exact schema, see `EnveKeep/Model/Models.swift` and `EnveKeep/Data/BackupArchive.swift`.

There are three versions:

- **Version 1** is the format Enve Keep for Android reads and writes. Enve Keep for iOS imports it unchanged, and it exports version 1 whenever there are no receipts.
- **Version 2** introduced `receipts` and `receiptAttachments` for scanned pages. Existing version 2 backups still import, with any newer details left blank.
- **Version 3** is written when you have receipts. It keeps the version 2 structure and adds searchable receipt details (`purchaseTime` as `HH:mm`, fuel amounts as decimal strings, and `customFields` as name/value pairs). Older iOS builds reject version 3 rather than silently dropping those fields. The version 1 keys keep their exact shape, so Enve Keep for Android rejects version 3 as newer rather than silently dropping receipts. Keep a separate version 1 backup if you need to restore data on Android.

## Building

Requirements: Xcode 26 or newer and [XcodeGen](https://github.com/yonaskolb/XcodeGen). The only dependency is [ZIPFoundation](https://github.com/weichsel/ZIPFoundation), which Swift Package Manager resolves.

```sh
xcodegen generate
xcodebuild -project EnveKeep.xcodeproj -scheme EnveKeep \
  -destination "platform=iOS Simulator,name=iPhone Air" build test
```

Minimum iOS version: 17.0.

Run the commands above from `ios/`. The app (`com.enve.keep`) and its share extension (`com.enve.keep.share`) share the App Group `group.com.enve.keep`, declared in `EnveKeep/EnveKeep.entitlements` and `ShareExtension/ShareExtension.entitlements`. Simulator builds need no setup. To run on a device, choose your team for both targets in Xcode. Your signing setup must support the two bundle IDs and the App Group. If you change the bundle ID prefix, use a matching App Group ID in both entitlements files and in `SharedInbox.appGroup`.

## Project layout

- `Model/`: records, settings and the `Day` calendar-date type.
- `Domain/`: renewal math, deadline status, money parsing, search, receipt text parsing and organizing.
- `App/`: app entry point, navigation, the Scan Receipt App Intent and handling of shared files and shortcut requests.
- `Data/`: the atomic JSON store, attachment storage (including PDF page rendering), backup archive and import/export, and on-device text recognition.
- `Reminders/`: local notification scheduling.
- `UI/`: SwiftUI screens, one folder per section, plus shared components.
- `Shared/`: the shared-file inbox, compiled into both the app and the extension.
- `ShareExtension/`: the "Save to Enve Keep" share extension. It only copies files into the inbox and never reads or writes your records.

## License

GNU Affero General Public License v3.0 only (`AGPL-3.0-only`). See [LICENSE](../LICENSE) and [third-party notices](../THIRD_PARTY_NOTICES.md).
