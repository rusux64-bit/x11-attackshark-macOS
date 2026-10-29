# Attack Shark X11 Control for macOS

SharkControl is a native macOS SwiftUI utility for monitoring an ATTACK SHARK X11 mouse connected by USB cable or its 2.4 GHz receiver. It detects compatible HID devices, displays connection and battery status, and provides a live mouse-input visualization.

## Features

- Detects ATTACK SHARK X11 wired and 2.4 GHz receiver HID endpoints
- Shows connection type, charging state, and battery heartbeats
- Provides a live SwiftUI mouse-button and scroll-wheel visualizer
- Includes a Swift package for DPI report encoding and decoding, with tests

Bluetooth connections are not supported by the current application.

## Requirements

- macOS
- Xcode (the project currently targets macOS 26.6 or later)
- An ATTACK SHARK X11 mouse connected by USB cable or its 2.4 GHz receiver for hardware functionality

## Build and run

1. Clone the repository.
2. Open `SharkControl.xcodeproj` in Xcode.
3. Select the `MyApp` scheme and **My Mac** as the run destination.
4. Build and run the app (`⌘R`).

The app uses Apple frameworks only; the Xcode target has no third-party package dependencies.

## Protocol package tests

The repository also includes `Package.swift`, which defines the `SharkControlProtocol` package and its DPI codec tests. Run them from the repository root:

```sh
swift test
```

## Project layout

- `SharkControl.xcodeproj` — macOS app project and build settings
- `Views`, `ViewModels`, `Services`, `InteractiveMouse` — SwiftUI interface and HID input handling
- `Protocol` — shared mouse protocol definitions and DPI codec
- `Tests` — Swift Testing coverage for DPI report encoding and decoding

## License

This project is licensed under the GNU General Public License v3.0. See [LICENSE](LICENSE).
