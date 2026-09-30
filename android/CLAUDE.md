# Enve Keep Android

Android app in the shared Enve Keep repository for tracking product warranties, subscriptions, and document expiry dates. Work on `main` with origin `https://github.com/opisaac9001/Enve-Keep.git`. Run Git operations from the repository root and Android build commands from `android/`. Read `../AGENTS.md` too. Original source uses the repository root's AGPL-3.0-only license. The iOS sibling is in `../ios/`; receipts and OCR remain iOS-only.

Use Kotlin and Jetpack Compose. Keep all user content on device. Do not add analytics, ads, accounts, network APIs, payments, or Internet permission. Use original code, branding, and artwork; the Stash it Reddit post is a feature reference only.

Before editing or building, run `pwd`, `git remote get-url origin`, and `git branch --show-current` (expected `main`). Keep changes within this repository. Build with `./gradlew :app:assembleDebug` using `ANDROID_HOME=/Volumes/games/Android` and a local JDK. For user-facing changes, install and exercise the app on an Android device or emulator. Report build errors and new warnings accurately.
