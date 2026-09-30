# Enve Keep

A free, open source Android app for keeping track of product warranties, subscriptions and document expiry dates. Everything stays on your phone.

Inspired by the [Stash it project post](https://www.reddit.com/r/vibecoding/comments/1wtouy3/warranty_subscriptions_and_documents_expiry/). Enve Keep is an independent implementation with its own code and design.

## Features

- **Dashboard** — past-due items (expired documents, missed renewals, recently ended warranties), what's coming up within your reminder windows, and an overview of each category.
- **Warranties** — products with brand, model, serial number, purchase date, retailer, price and currency, warranty end date (with 1/2/3/5-year shortcuts), notes, and any number of receipts, photos or PDFs. Share a product's details as text when making a claim.
- **Subscriptions** — price, currency, billing cycle (every N days/weeks/months/years) and next renewal. Renewals follow the original billing date, so a plan billed on the 31st renews on the last day of shorter months and returns to the 31st afterwards. Mark a renewal as paid, mark a subscription canceled or reactivate it. Shows an estimated monthly spend per currency.
- **Documents** — passports, licences, insurance and the like, with issuer, document number, issue and expiry dates, notes and attachments.
- **Attachments** — pick files or take a photo. Files are copied into app-private storage, so they remain available after a reboot or if the original is deleted. Attachments open and share through the system viewer and share sheet with per-file, temporary read access.
- **Search and filters** — search everything from the dashboard, or search and filter within each list.
- **Reminders** — a daily local check posts a notification when a date enters its reminder window (configurable per category) and again when it arrives. Android 13+ notification permission is requested from within the app.
- **Backup** — export all records, attachments and settings to a single ZIP file you choose, and import it on the same or another device. Imports are validated first, reject any archive entry outside the expected layout (including path traversal), and leave existing data untouched if anything is wrong.
- Light, dark and system themes; content descriptions and headings for screen readers.

## Privacy

Enve Keep does not request the Internet permission. It has no accounts, servers, analytics, ads or in-app purchases. Your records and files are stored only in the app's private storage on your device and are excluded from Android cloud backup and device-to-device transfer; the only way data leaves the app is when you export a backup or share a file yourself.

## Building

Requirements: JDK 17 or newer and the Android SDK (compile SDK 36.1).

```sh
export ANDROID_HOME=/path/to/Android/sdk
./gradlew :app:assembleDebug          # APK at app/build/outputs/apk/debug/
./gradlew :app:testDebugUnitTest      # unit tests
./gradlew :app:installDebug           # install on a connected device
```

Minimum Android version: 8.0 (API 26).

## Project layout

- `data/` — Room entities and DAO, repository, attachment storage, settings (DataStore), backup archive format.
- `domain/` — renewal calculation, deadline status, amount parsing and formatting, search matching.
- `reminders/` — WorkManager worker and notification posting.
- `ui/` — Jetpack Compose screens, one package per section, plus shared components and theme.

## License

MIT — see [LICENSE](LICENSE).
