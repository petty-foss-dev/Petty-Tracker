# Contributing to Enve Keep

Thanks for helping improve Enve Keep. The app is free, keeps records on the device, and uses native iOS APIs. Contributions should preserve those choices.

## Report a bug

Open an [issue](https://github.com/opisaac9001/Enve-Keep-iOS/issues/new/choose) with the iOS version, device or simulator, steps to reproduce, and expected versus actual behavior. Include the app commit or version when you know it.

Use fictional or redacted receipts and screenshots. Remove names, addresses, payment details, document numbers, and other personal information before posting. For recognition bugs, include the relevant redacted text and the field that was misread.

## Propose a change

For a large feature, start with an issue so its behavior and scope can be discussed. Focus each pull request on one change and explain what the user will experience.

Original contributions are accepted under `AGPL-3.0-only`, the project's license. Keep third-party license and attribution notices when adding permitted dependencies or materials; identify their source in your pull request.

## Develop locally

Follow the [README setup](README.md#build-and-run). Use Swift 6, SwiftUI, and the iOS 17 minimum target. Run `xcodegen generate` after changing `project.yml`.

Keep receipt parsing conservative: retain the original OCR text, leave ambiguous fields blank, and keep all extracted fields editable. Preserve the backup contract and add a format version when a change would otherwise lose data in older readers.

## Verify your change

- Build the app and share extension, and resolve new errors and warnings.
- Run relevant tests for changes to parsing, persistence, backup, dates, or exports.
- Exercise changed screens in Simulator, including accessibility labels and light/dark appearance where relevant.
- Test camera behavior on a physical iPhone and state when device verification is still outstanding.
- Update documentation for changes to user behavior or setup.

In the pull request, describe the change, how you checked it, and any remaining limits. Do not commit signing credentials, personal records, DerivedData, or build products.
