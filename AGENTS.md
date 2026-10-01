# petty: Tracker repository guide

This repository contains the native iOS and Android apps. Use `main` with origin `https://github.com/petty-foss-dev/Petty-Tracker.git`. Run Git commands from the repository root and platform build commands from `ios/` or `android/`.

Before making changes, check the path, origin, branch, and working tree, then read the matching platform's `CLAUDE.md`. Preserve unrelated work. Keep changes limited to the requested outcome.

All records stay on the device. Do not add accounts, analytics, ads, payment gates, Internet permission, or a network service. Use original code and artwork. Receipts and OCR are currently iOS-only; Android supports warranties, subscriptions, documents, and attachments. The version 1 ZIP backup contract is shared; version 3 includes iOS receipts.

Codex owns review, testing, device and simulator verification, and source control. Implementation delegates must not commit, push, merge, change branches, or publish. Generated changes must be reviewed before they are built and exercised locally.

Build iOS from `ios/` using the PettyTracker scheme on an iPhone Air simulator. Build Android from `android/` with `./gradlew :app:assembleDebug`. Run relevant tests and exercise changed screens. Report zero errors and zero new warnings, or state the exact blocker.

Original source is licensed under AGPL-3.0-only. Preserve third-party notices. Never commit personal records, credentials, local SDK paths, signing files, or build products.
