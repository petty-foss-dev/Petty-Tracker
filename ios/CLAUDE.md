# Enve Keep iOS

Standalone iOS companion to Enve Keep Android. Work on `main` in this repository. Before editing or building, run `pwd`, `git remote get-url origin` (expected `https://github.com/opisaac9001/Enve-Keep-iOS.git`), and `git branch --show-current` (expected `main`). Do not edit other Enve repositories.

Use Swift 6 and SwiftUI with iOS 17.0 minimum. All records and attachments stay on device. No accounts, analytics, ads, payments, or network service. Use original code and artwork. The Android project at `/Volumes/games/enveworkspace/Enve Keep Android` is read-only prior art; its `backup.json` ZIP format is the cross-platform data contract.

Generate the Xcode project with `xcodegen generate` if `project.yml` changes. Build the `EnveKeep` scheme on an iPhone Air simulator with DerivedData under `/Volumes/games/EnveBuildTmp/DerivedData-keep-ios`. Run tests and exercise UI changes in Simulator. Do not commit, add a remote, push, or publish as an implementation delegate; Codex handles source control and final verification.
