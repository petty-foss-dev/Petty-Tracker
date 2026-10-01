# Third-party notices

Third-party components retain their own licenses, separate from petty: Tracker's original source.

## iOS

| Component | Pinned version | License | Use |
| --- | --- | --- | --- |
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | 0.9.20 | MIT | Reading and writing ZIP backups |

Copyright (c) 2017–2025 Thomas Zoechling (https://www.peakstep.com).

The full license is retained in [docs/licenses/ZIPFoundation-MIT.txt](docs/licenses/ZIPFoundation-MIT.txt). The dependency revision is recorded in `ios/PettyTracker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

Apple system frameworks are provided by the platform and are not vendored in this repository.

## Android

| Component | License | Use |
| --- | --- | --- |
| AndroidX: Core, Activity, Lifecycle, Navigation, Room, WorkManager, DataStore, ExifInterface, Compose, and Material | Apache-2.0 | Native UI, persistence, reminders, and attachment handling |
| Kotlin standard library and kotlinx.serialization | Apache-2.0 | Language runtime and JSON serialization |
| JUnit 4.13.2 | EPL-1.0 | Unit tests only; [license text](docs/licenses/JUnit-EPL1.txt) |
| Gradle wrapper | Apache-2.0 | Build bootstrap; its embedded license is also retained in [docs/licenses/Gradle-Wrapper-Apache2.txt](docs/licenses/Gradle-Wrapper-Apache2.txt) |

Versions and Maven coordinates are recorded in `android/gradle/libs.versions.toml` and `android/app/build.gradle.kts`. Gradle resolves these packages and their transitive dependencies; their upstream license and notice files remain applicable. Build plugins and the Android SDK are development tools and retain their respective licenses. Android dependencies are not relicensed by the project's AGPL license.
