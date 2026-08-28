# Helium Passpoint SDK

Drop this SDK into your carrier app to let subscribers automatically connect to Helium WiFi hotspots and brownfield coverage via Passpoint (Hotspot 2.0).

One repository ships three SDKs. The React Native package is a thin bridge over the same Swift and Kotlin code the native packages expose directly, so all three behave identically.

| Your app | Package | Install |
| --- | --- | --- |
| React Native | `@helium/passpoint-sdk` (npm) | `pnpm add @helium/passpoint-sdk` |
| Native iOS | `HeliumPasspoint` (SwiftPM / CocoaPods) | [see below](#native-ios-swift) |
| Native Android | `com.helium.passpoint:passpoint-sdk` (Maven) | [see below](#native-android-kotlin) |

---

## React Native

```sh
pnpm add @helium/passpoint-sdk
```

### iOS setup

The SDK requires **iOS 15.0**. React Native's app template still defaults to 13.4, so raise the floor in `ios/Podfile` before installing or CocoaPods will refuse to resolve:

```ruby
platform :ios, '15.0'
```

```sh
cd ios && pod install
```

Then in Xcode:

1. **Signing & Capabilities** → add **Hotspot Configuration**
2. **Signing & Capabilities** → add **Keychain Sharing** with group:
   ```
   $(AppIdentifierPrefix)com.apple.networkextensionsharing
   ```
3. **Note your Team ID** (visible under Signing & Capabilities). You need it for the `keychainAccessGroup` option.

No additional SPM packages or CocoaPods are required — the SDK uses only Apple's built-in Security framework.

### Android setup

Ensure your app's `build.gradle` has `minSdk 26` or higher, and add the BouncyCastle packaging excludes (see [Android packaging](#android-packaging)).

The SDK declares the permissions it needs; they merge automatically. You must request `ACCESS_FINE_LOCATION` at runtime **before** calling `install()`, or it rejects with `PERMISSION_DENIED`.

### 1. Wrap your app in the provider

```tsx
import { PasspointProvider } from "@helium/passpoint-sdk";

export default function App() {
  return (
    <PasspointProvider
      config={{
        apiKey: "your-api-key",
        // iOS: required for Passpoint profile installation
        keychainAccessGroup: "YOUR_TEAM_ID.com.apple.networkextensionsharing",
      }}
    >
      <YourApp />
    </PasspointProvider>
  );
}
```

### 2. Use the hook in any screen

```tsx
import {
  usePasspoint,
  PasspointError,
  PasspointErrorCode,
} from "@helium/passpoint-sdk";

function WifiScreen({ subscriberId }) {
  const { isInstalled, install, remove, isLoading, error } = usePasspoint();

  const handleInstall = async () => {
    try {
      await install(subscriberId);
    } catch (e) {
      if (e instanceof PasspointError) {
        if (e.code === PasspointErrorCode.PERMISSION_DENIED) {
          // prompt user for location permission
        }
      }
    }
  };

  if (isInstalled === null) return <Loading />;

  return isInstalled ? (
    <Button onPress={remove}>Remove WiFi Profile</Button>
  ) : (
    <Button onPress={handleInstall} disabled={isLoading}>
      Enable WiFi Offload
    </Button>
  );
}
```

Runnable example: [`examples/react-native/`](examples/react-native/).

---

## Native iOS (Swift)

### Install

**Swift Package Manager** — in Xcode, *File → Add Package Dependencies*, or in `Package.swift`:

```swift
.package(url: "https://github.com/novalabsxyz/passpoint-sdk.git", from: "1.0.0")
```

**CocoaPods**:

```ruby
pod 'HeliumPasspoint', :git => 'https://github.com/novalabsxyz/passpoint-sdk.git', :tag => 'v1.0.0'
```

### Entitlements

Same two capabilities as the React Native integration — the SDK cannot install a profile without them:

1. **Hotspot Configuration** (`com.apple.developer.networking.HotspotConfiguration`)
2. **Keychain Sharing** with group `$(AppIdentifierPrefix)com.apple.networkextensionsharing`

### Use

```swift
import HeliumPasspoint

let client = PasspointClient.shared

try client.configure(PasspointConfig(
  apiKey: "your-api-key",
  environment: .production,
  keychainAccessGroup: "YOUR_TEAM_ID.com.apple.networkextensionsharing"
))

do {
  try await client.install(subscriberID: "subscriber-123")
} catch let error as PasspointError {
  switch error.code {
  case .simulatorNotSupported: print("run on a device")
  case .apiUnauthorized:       print("bad API key")
  default:                     print(error.message)
  }
}

await client.isInstalled()                              // Bool
await client.certificateInfo()                          // CertificateInfo
try await client.remoteStatus(subscriberID: "sub-123")  // RemoteProfileStatus?
try await client.remove()
await client.diagnostics()                              // [String: String] for support
```

Everything is `async`, so no call blocks the caller, and the client is safe to use from several tasks at once: `install()` and `remove()` are serialised against each other, while the read-only queries stay responsive during an install. `PasspointClient` is `Sendable` and builds clean under Swift 6 complete strict-concurrency checking.

Passpoint is unavailable on the simulator — `install()` and `remove()` throw `.simulatorNotSupported` there.

Runnable example: [`examples/ios-swift/`](examples/ios-swift/).

---

## Native Android (Kotlin)

### Install

```kotlin
dependencies {
  implementation("com.helium.passpoint:passpoint-sdk:1.0.0")
}
```

`minSdk` must be 26 or higher.

### Android packaging

BouncyCastle ships duplicate OSGi metadata across `bcprov` and `bcpkix`, which Android's resource merger will not resolve on its own. Every app that pulls in the SDK — React Native included — needs this in its app-level Gradle file:

```kotlin
android {
  packaging {
    resources {
      excludes += setOf(
        "META-INF/versions/9/OSGI-INF/MANIFEST.MF",
        "META-INF/DEPENDENCIES",
      )
    }
  }
}
```

### Use

```kotlin
import com.helium.passpoint.*

val client = PasspointClient.getInstance(context)
client.configure(PasspointConfig(apiKey = "your-api-key"))

// install/remove/getRemoteStatus block on network and crypto — never call them
// on the main thread.
withContext(Dispatchers.IO) {
  try {
    client.install("subscriber-123")
  } catch (e: PasspointException) {
    when (e.code) {
      PasspointErrorCode.PERMISSION_DENIED -> requestLocationPermission()
      PasspointErrorCode.API_UNAUTHORIZED -> reportBadApiKey()
      else -> log(e.message)
    }
  }

  // Also blocking — these hit the network or the Wi-Fi framework.
  client.getRemoteStatus("subscriber-123")  // RemoteProfileStatus?
  client.remove()
}

// Cheap local reads; safe from any thread.
client.isInstalled()                        // Boolean
client.getCertificateInfo()                 // CertificateInfo
client.diagnostics()                        // Map<String, String> for support
```

`install()` requires `ACCESS_FINE_LOCATION` to have been granted at runtime. The SDK declares the manifest permissions; prompting is the app's job.

Like the iOS SDK, the client is safe to use from several threads: `install()` and `remove()` are serialised against each other, and the read-only queries are not gated.

**EAP-TLS only.** An Android Passpoint profile is built from a certificate credential, which is EAP-TLS by construction, so `configure()` rejects `EapType.TTLS` and `EapType.PEAP` with `INVALID_CONFIG` rather than accepting them and quietly provisioning EAP-TLS anyway. iOS accepts all three.

**Private key storage.** The keypair lives in `Context.getNoBackupFilesDir()`, not SharedPreferences, so it is excluded from Auto Backup and device-to-device transfer without any manifest change on your side. A keypair written by an SDK version before 0.2 is migrated out of SharedPreferences and erased there on first use.

Runnable example: [`examples/android-kotlin/`](examples/android-kotlin/).

---

## Subscriber IDs

Every call to `install()` and `getRemoteStatus()` takes a `subscriberId` — an opaque string you pick to identify the subscriber in your own system. The SDK doesn't interpret or validate it beyond requiring a non-empty string.

Rules of thumb:

- Use the **same `subscriberId`** for `install()` and any later `getRemoteStatus()` call. The server associates the issued certificate with that ID, so a mismatch will look like "no profile installed."
- Re-calling `install()` with the same `subscriberId` revokes the previous certificate for that subscriber and issues a fresh one.
- `subscriberId` should be stable per-subscriber across reinstalls if you want server-side continuity (e.g. stats, revocation). If you don't care, any unique string works.

## Environments

`environment` selects the Helium inventory API base URL. The SDK appends `/preset/profile/generate` and `/preset/profile/status` to it. An unrecognised name falls back to production rather than throwing.

| Name | Base URL |
| --- | --- |
| `production` (default) | `https://api.prod.hib.nova.xyz/api/inventory/v1` |
| `development` | `https://api-dev.dev.hib.nova.xyz/api/inventory/v1` |
| `poc` | `https://api.dev.hib.nova.xyz/api/inventory/v1` |

```ts
// TypeScript — a string starting with http is used verbatim as a custom deployment
{ apiKey: 'pk_xxx', environment: 'https://your-api.example.com/api/inventory/v1' }
```

```swift
// Swift
PasspointConfig(apiKey: "pk_xxx", environment: .custom(URL(string: "https://…/api/inventory/v1")!))
```

```kotlin
// Kotlin
PasspointConfig(apiKey = "pk_xxx", environment = PasspointEnvironment.Custom("https://…/api/inventory/v1"))
```

## Custom server CA

If you're using RADIUS infrastructure with a different CA, pass its PEM at configure time (`serverCaCertPem` / `serverCACertificatePEM`). Otherwise the SDK uses the CA it bundles.

## Preset ID

If your partner account has more than one EAP-TLS preset, supply the UUID of the one to use (`presetId` / `presetID`). Partners with a single preset can leave it unset.

## `isInstalled()` vs `getRemoteStatus()`

| Method | Checks | Network | Returns |
| --- | --- | --- | --- |
| `isInstalled()` | Local state (see below) | No | `boolean` |
| `getRemoteStatus()` | Helium inventory API | Yes | `RemoteProfileStatus` or `null` (no profile) |

Use `isInstalled()` for fast UI checks. Use `getRemoteStatus()` to reconcile against the server — for example, to detect that a profile was revoked from another device.

`isInstalled()` reads different things on each platform, because the two operating systems expose different things:

- **iOS** — the client certificate in the keychain. From iOS 26, `getConfiguredSSIDs` no longer reports Hotspot 2.0 domains, so the keychain is the only reliable signal.
- **Android** — a flag the SDK writes on a successful install. `WifiManager` offers no way to ask whether a given Passpoint profile is still present, so a profile the **user** deletes in Settings keeps reporting as installed until the SDK's own `remove()` runs.

> **Android caveat.** Android keeps the issued certificate inside the system's `PasspointConfiguration` and never hands it back, so `getCertificateInfo()` returns `null` for `expiresAt` and `subject` there. Use `getRemoteStatus()` when you need an authoritative expiry on Android.

## Error handling

Every SDK operation fails with one type carrying a machine-readable code: `PasspointError` (TypeScript, Swift) or `PasspointException` (Kotlin). All three declare the identical code set, defined once in [`core/contract/contract.json`](core/contract/contract.json) and asserted by each platform's test suite.

Codes marked for one platform are still *declared* on all three, so a single `switch`/`when` compiles everywhere. "Thrown by" is what actually reaches you at runtime:

| Code | Thrown by | Description |
| --- | --- | --- |
| `NOT_CONFIGURED` | All | SDK not initialized |
| `INVALID_CONFIG` | All | Bad config (empty apiKey / subscriberId, unknown eapType, or a non-TLS eapType on Android) |
| `PLATFORM_NOT_SUPPORTED` | React Native | Running on web or an unsupported platform |
| `SIMULATOR_NOT_SUPPORTED` | iOS | Passpoint requires a physical device |
| `PERMISSION_DENIED` | Android | `ACCESS_FINE_LOCATION` not granted |
| `KEYPAIR_GENERATION_FAILED` | All | RSA keypair generation failed |
| `CSR_GENERATION_FAILED` | All | Certificate signing request failed |
| `NETWORK_ERROR` | All | Can't reach the Passpoint API |
| `API_ERROR` | All | API returned an error response, or an undecodable body |
| `API_UNAUTHORIZED` | All | API key rejected (401/403) |
| `API_RATE_LIMITED` | All | Too many requests (429) |
| `CERTIFICATE_PARSE_FAILED` | Android; iOS only for a missing bundled CA | Couldn't parse a certificate |
| `CERTIFICATE_SAVE_FAILED` | iOS | Keychain save failed, or an unparseable PEM |
| `IDENTITY_LOAD_FAILED` | iOS | Couldn't build a TLS identity — usually a Keychain Sharing misconfiguration |
| `PROFILE_INSTALL_FAILED` | All | OS rejected the Passpoint profile, including the user dismissing the iOS dialog |
| `WIFI_MANAGER_UNAVAILABLE` | Android | WifiManager service unavailable |
| `NETWORK_SUGGESTION_DISALLOWED` | Android | User blocked the app from adding WiFi |
| `NETWORK_SUGGESTION_LIMIT` | Android | Exceeded max suggestions per app |
| `UNKNOWN` | All | Unexpected error |

**Declared but never thrown.** These exist so the enum is stable across SDK versions and platforms; do not branch on them expecting them to fire today:
`INVALID_API_KEY`, `MISSING_ENTITLEMENTS`, `CERTIFICATE_NOT_FOUND`, `PROFILE_INSTALL_CANCELLED`, `PROFILE_NOT_FOUND`, `PROFILE_REMOVE_FAILED`, `REMOVE_FAILED`.

In particular, a missing Hotspot Configuration entitlement surfaces as `PROFILE_INSTALL_FAILED` (not `MISSING_ENTITLEMENTS`), a dismissed iOS install dialog as `PROFILE_INSTALL_FAILED` (not `PROFILE_INSTALL_CANCELLED`), and `remove()` is idempotent so it never reports "nothing installed".

## React Native API reference

### `<PasspointProvider config={...}>`

```ts
interface PasspointConfig {
  apiKey: string; // required
  environment?: "production" | "development" | "poc" | string; // or a custom base URL
  eapType?: EapType; // EapType.TLS (default) | EapType.TTLS | EapType.PEAP
  serverCaCertPem?: string; // custom CA cert PEM
  keychainAccessGroup?: string; // iOS only: '<TEAM_ID>.com.apple.networkextensionsharing'
  presetId?: string; // only if your account has multiple EAP-TLS presets
}
```

### `usePasspoint()`

```ts
interface UsePasspointResult {
  isInstalled: boolean | null; // null while loading
  certificateInfo: CertificateInfo | null;
  install: (subscriberId: string) => Promise<InstallResult>;
  remove: () => Promise<RemoveResult>;
  getRemoteStatus: (subscriberId: string) => Promise<RemoteProfileStatus | null>;
  refresh: () => Promise<void>;
  isLoading: boolean;
  error: PasspointError | null;
}
```

### `PasspointSDK` (imperative)

```ts
import { PasspointSDK } from "@helium/passpoint-sdk";

const sdk = PasspointSDK.configure({ apiKey: "your-key" });
await sdk.install("sub-123");
await sdk.isInstalled();
await sdk.getCertificateInfo();
await sdk.getRemoteStatus("sub-123");
await sdk.remove();
```

### Result types

```ts
interface CertificateInfo {
  isInstalled: boolean;
  expiresAt: string | null; // ISO 8601; always null on Android
  subject: string | null;   // always null on Android
  domain: string | null;
  friendlyName: string | null;
}

interface RemoteProfileStatus {
  subscriberId: string;
  presetId: string;
  eapType: number;   // 13 = EAP-TLS
  expiresAt: string; // ISO 8601
  active: boolean;   // false once the cert has expired
}
```

## Requirements

- React Native >= 0.73 (for the npm package)
- iOS >= 15.0, physical device only
- Android API >= 26 (`minSdk 26`)

## Contributing

See [ARCHITECTURE.md](ARCHITECTURE.md) for the repository layout, how the three SDKs share code, and how to run all three test suites.

## License

Apache-2.0 — see [LICENSE](./LICENSE).
