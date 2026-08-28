# Native iOS example

A SwiftUI screen driving the full SDK lifecycle: configure → install → inspect
→ reconcile with the server → remove.

- `PasspointViewModel.swift` — all the SDK calls, with error handling per code
- `PasspointScreen.swift` — the UI

## Build it

```sh
swift build --triple arm64-apple-ios15.0 --sdk "$(xcrun --sdk iphoneos --show-sdk-path)"
```

This is a real package that depends on the SDK as a separate module, which is
why CI builds it: if anything the example needs stops being `public`, this
fails.

## Run it on a device

The package is a library, not an app — there is no `.xcodeproj` here because a
generated one would rot. To try it:

1. New Xcode project → App → SwiftUI.
2. *File → Add Package Dependencies → Add Local…* and pick this directory
   (or add `https://github.com/helium/passpoint-sdk.git` and copy the two
   source files in).
3. **Signing & Capabilities** → add **Hotspot Configuration**.
4. **Signing & Capabilities** → add **Keychain Sharing** with group
   `$(AppIdentifierPrefix)com.apple.networkextensionsharing`.
5. In `ContentView`:
   ```swift
   PasspointScreen(
     apiKey: "your-partner-api-key",
     subscriberID: "subscriber-123",
     teamID: "YOUR_TEAM_ID"
   )
   ```
6. Run on a **physical device**. Passpoint is not available on the simulator;
   `install()` throws `SIMULATOR_NOT_SUPPORTED` there.

## If install fails

| Error code | Usual cause |
| --- | --- |
| `SIMULATOR_NOT_SUPPORTED` | Running on the simulator |
| `IDENTITY_LOAD_FAILED`, `CERTIFICATE_SAVE_FAILED` | Keychain Sharing group missing, or the wrong Team ID in `keychainAccessGroup` |
| `PROFILE_INSTALL_FAILED` | Hotspot Configuration capability missing |
| `API_UNAUTHORIZED` | API key rejected |

`await client.diagnostics()` returns a state dump worth attaching to a support
ticket. It never contains the API key.
