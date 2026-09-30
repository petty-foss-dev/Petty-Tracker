# petty: Tracker for iOS

The native iPhone app in the shared [petty: Tracker repository](../README.md). Built with Swift 6 and SwiftUI for iOS 17 or later.

Keep warranties, subscriptions, documents, and receipts on your device. iOS includes receipt scanning and OCR, line items, fuel details, routes and custom fields, a review inbox, product links, CSV and warranty claim PDF exports, and a Share extension.

See the [screenshots and feature overview](../README.md#a-look-inside) and [full feature and backup reference](../docs/ios-reference.md).

## Build

From this folder, with Xcode 26 or later and XcodeGen installed:

```sh
xcodegen generate
open EnveKeep.xcodeproj
```

Choose the EnveKeep scheme and an iPhone simulator. From Terminal:

```sh
xcodebuild -project EnveKeep.xcodeproj -scheme EnveKeep \
  -destination 'platform=iOS Simulator,name=iPhone Air' \
  CODE_SIGNING_ALLOWED=NO build test
```

For a physical iPhone, set your development team on both EnveKeep and EnveKeepShare. See the [shared build guide](../README.md#ios) for signing and App Group details. Camera capture requires a real iPhone; use Photos, Files, or manual entry in Simulator.

## License and support

Original source is licensed under [AGPL-3.0-only](../LICENSE). See [third-party notices](../THIRD_PARTY_NOTICES.md).
