# petty: Tracker iOS

iOS app in the shared petty: Tracker repository. Work on `main`. Before editing or building, run `pwd`, `git remote get-url origin` (expected `https://github.com/petty-foss-dev/Petty-Tracker.git`), and `git branch --show-current` (expected `main`). Run Git operations from the repository root and iOS build commands from `ios/`. Read `../AGENTS.md` too.

Use Swift 6 and SwiftUI with iOS 17.0 minimum. All records and attachments stay on device. No accounts, analytics, ads, payments, or network service. Use original code and artwork. The Android project is in `../android/`; its version 1 `backup.json` ZIP format is the cross-platform data contract. Receipts are iOS-only. Original source uses the repository root's AGPL-3.0-only license.

Generate the Xcode project with `xcodegen generate` if `project.yml` changes. Build the `EnveKeep` scheme on an iPhone Air simulator with DerivedData under `/Volumes/games/EnveBuildTmp/DerivedData-keep-ios`. Run tests and exercise UI changes in Simulator. Do not commit, add a remote, push, or publish as an implementation delegate; Codex handles source control and final verification.
