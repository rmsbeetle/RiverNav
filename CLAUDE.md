# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

RiverNav is an iOS SwiftUI app (iPhone only, bundle ID `rms.RiverNav`). Targets iOS 17.0+. Swift 5.0. Uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES` — all declarations are `@MainActor` by default; delegate/callback methods must be marked `nonisolated` explicitly.

## Dependencies

- **MapLibre** via SPM: `https://github.com/maplibre/maplibre-native`, product `MapLibre`, upToNextMajorVersion from 6.0.0. UIKit classes use the `MLN` prefix (e.g. `MLNMapView`).

After cloning, resolve packages before building:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project RiverNav.xcodeproj -scheme RiverNav -resolvePackageDependencies
```

## Build & Test

```bash
# Build for simulator
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project RiverNav.xcodeproj -scheme RiverNav \
  -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run unit tests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project RiverNav.xcodeproj -scheme RiverNav \
  -destination 'platform=iOS Simulator,name=iPhone 16' test

# Run a single test class
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project RiverNav.xcodeproj -scheme RiverNav \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:RiverNavTests/RiverNavTests test
```

`xcode-select` points to CommandLineTools by default on this machine; always prefix with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Architecture

```
RiverNav/
├── RiverNavApp.swift       # @main entry, WindowGroup → ContentView
├── ContentView.swift       # Root SwiftUI view
├── Models/
│   ├── Route.swift         # Route(id, name, waypoints:[CLLocationCoordinate2D], createdAt)
│   └── NavigationSession.swift  # NavigationSession(routeId, state:.idle/.active/.paused, startedAt, pausedAt?)
├── Views/
│   └── MapView.swift       # UIViewRepresentable wrapping MLNMapView
└── Services/
    └── LocationService.swift  # @Observable CLLocationManager wrapper; requestPermission/startUpdating/stopUpdating
```

The project uses `PBXFileSystemSynchronizedRootGroup` — new Swift files added anywhere under `RiverNav/` are automatically compiled without touching `.pbxproj`.

Info.plist is auto-generated (`GENERATE_INFOPLIST_FILE = YES`). Location permission string is set via build setting `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` in the target configs, not in a manual plist file.
