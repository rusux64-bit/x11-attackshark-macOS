X11 Software

A native macOS app for configuring the ATTACK SHARK X11 mouse. Built with SwiftUI for Apple Silicon and Intel Macs, it talks to the mouse directly over USB HID, with no background services and no third-party dependencies.

> This is an unofficial, community project. It is not affiliated with or endorsed by ATTACK SHARK. Writing settings to a mouse carries some risk, so use it at your own discretion.

## Features

- **Device detection** for the ATTACK SHARK X11 over USB cable or its 2.4 GHz receiver.
- **Connection and battery status**: connection type, charging state, and battery level.
- **Live test panel**: an illustration of the mouse that lights up as you press buttons and scroll the wheel.
- **DPI tab, synced with the mouse**:
  - Reads the stages the mouse is holding (enabled state, DPI value, colour, and active stage).
  - Sends changes to the mouse after you stop editing, then reads them back to confirm.
  - Follows the mouse's own DPI button, so the active stage stays up to date.
  - A status badge shows whether the app is synced, with a refresh button to re-read the mouse.
- **Other tabs** (Performance, Buttons, Lighting, Power) are an interface preview. Their changes are not sent to the mouse yet.
- **Light and dark themes.**

Bluetooth is not supported.

## Requirements

- macOS (the project currently targets macOS 26.6 or later).
- Xcode with the matching SDK, to build from source.
- An ATTACK SHARK X11 connected by USB cable or its 2.4 GHz receiver.

## Installation

### From a release

1. Download the `.dmg` from the [Releases](../../releases) page.
2. Open it and drag **X11 Software** into **Applications**.
3. The app is not signed or notarized, so macOS will block the first launch. Right-click the app, choose **Open**, and confirm. Or run:

   ```sh
   xattr -dr com.apple.quarantine "/Applications/X11 Software.app"
   ```

### Build from source

1. Clone the repository.
2. Open `SharkControl.xcodeproj` in Xcode.
3. Select the **MyApp** target and **My Mac** as the run destination.
4. Press `⌘R`.

To build from the command line without code signing:

```sh
xcodebuild build \
  -project SharkControl.xcodeproj \
  -target MyApp \
  -configuration Release \
  CODE_SIGNING_ALLOWED=NO
```

## Running the tests

The protocol package (DPI report encoding and decoding) has its own tests:

```sh
swift build
swift test
```

## Releases and CI

- **CI** (`.github/workflows/ci.yml`) runs on every push and pull request. It builds and tests the protocol package, and compiles the app target.
- **Draft release** (`.github/workflows/release.yml`) is started manually from the Actions tab with a version such as `v1.0.0`. It builds an unsigned Release app, packages it into a DMG, and creates a draft GitHub release. The release notes list the commits since the previous tag, with emoji removed. Review the draft and publish it when you are ready.

## Project layout

| Folder | Contents |
|---|---|
| `Views/` | SwiftUI interface: dashboard, configuration panel, connection screen. |
| `ViewModels/` | `DeviceViewModel`, which connects the device to the interface and handles DPI sync. |
| `Services/` | HID device discovery and feature-report transport. |
| `Protocol/` | Mouse protocol definitions and the DPI codec. |
| `InteractiveMouse/` | Mouse input monitoring and the live test illustration. |
| `Tests/` | Swift Testing coverage for DPI report encoding and decoding. |
| `.github/` | CI and release workflows. |

For how the DPI report maps to the codec, see `PORTING_NOTES.md`.

## Contributing

Issues and pull requests are welcome. Please run `swift test` and make sure the app target compiles before opening a pull request.

## Photos
<img width="1051" height="700" alt="image" src="https://github.com/user-attachments/assets/fa738d72-187c-4475-b234-9ab265f2c681" />
<img width="1064" height="701" alt="image" src="https://github.com/user-attachments/assets/b87db1e1-5b44-4388-91a4-ad40b46b3514" />
<img width="1058" height="702" alt="image" src="https://github.com/user-attachments/assets/7048305b-6e06-4eb6-9c71-964bd80cfbf1" />
<img width="1059" height="705" alt="image" src="https://github.com/user-attachments/assets/b149d9e8-33c0-4955-9689-56d3d6e2a7c4" />
<img width="1063" height="704" alt="image" src="https://github.com/user-attachments/assets/9d6a7a82-ba78-4549-8fcd-ec95e398d9ff" />

## License

This project is licensed under the GNU General Public License v3.0. See [LICENSE](LICENSE).
