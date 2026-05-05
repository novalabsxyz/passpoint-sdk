# @helium/passpoint-sdk

Helium Passpoint WiFi Offload SDK for React Native.

Drop this SDK into your carrier app to let subscribers automatically connect to Helium WiFi hotspots and brownfield coverage via Passpoint (Hotspot 2.0).

## Installation

```sh
pnpm add @helium/passpoint-sdk
```

### iOS

```sh
cd ios && pod install
```

Then in Xcode:

1. **Signing & Capabilities** > add **Hotspot Configuration**
2. **Signing & Capabilities** > add **Keychain Sharing** with group:
   ```
   $(AppIdentifierPrefix)com.apple.networkextensionsharing
   ```
3. **Note your Team ID** (visible in Xcode under Signing & Capabilities). You'll need it for the `keychainAccessGroup` config option.

No additional SPM packages or CocoaPods are required — the SDK uses only Apple's built-in Security framework.

### Android

Ensure your app's `build.gradle` has `minSdk 26` or higher.

The SDK declares the required permissions (`ACCESS_FINE_LOCATION`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE`) in its own manifest -- they merge automatically.

**Important:** You must request `ACCESS_FINE_LOCATION` at runtime _before_ calling `install()`. The SDK will reject with `PERMISSION_DENIED` if the permission hasn't been granted.

## Quick Start

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

## Subscriber IDs

Every call to `install()` and `getRemoteStatus()` takes a `subscriberId` — an opaque string you pick to identify the subscriber in your own system. The SDK doesn't interpret or validate it beyond requiring a non-empty string.

Rules of thumb:

- Use the **same `subscriberId`** for `install()` and any later `getRemoteStatus()` call. The server associates the issued certificate with that ID, so a mismatch will look like "no profile installed."
- Re-calling `install()` with the same `subscriberId` revokes the previous certificate for that subscriber and issues a fresh one.
- `subscriberId` should be stable per-subscriber across reinstalls if you want server-side continuity (e.g. stats, revocation). If you don't care, any unique string works.

## API Reference

### `<PasspointProvider config={...}>`

Initializes the SDK. Wrap your app (or relevant subtree) in this provider.

```ts
interface PasspointConfig {
  apiKey: string; // required
  environment?: string; // 'production' (default) | 'staging' | 'development' | custom base URL
  eapType?: EapType; // EapType.TLS (default) | EapType.TTLS | EapType.PEAP
  serverCaCertPem?: string; // custom CA cert PEM (optional, uses bundled ISRG Root X1)
  keychainAccessGroup?: string; // iOS only: '<TEAM_ID>.com.apple.networkextensionsharing'
  presetId?: string; // optional, only needed if your partner account has multiple EAP-TLS presets
}
```

### `usePasspoint()`

React hook for all passpoint operations. Must be inside `<PasspointProvider>`.

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

For non-React usage or manual control:

```ts
import { PasspointSDK } from "@helium/passpoint-sdk";

const sdk = PasspointSDK.configure({ apiKey: "your-key" });
await sdk.install("sub-123");
await sdk.isInstalled();                 // local keychain/keystore check
await sdk.getCertificateInfo();
await sdk.getRemoteStatus("sub-123");    // server-side status (network call)
await sdk.remove();
```

### `isInstalled()` vs `getRemoteStatus()`

| Method              | Checks                    | Network | Returns                                   |
| ------------------- | ------------------------- | ------- | ----------------------------------------- |
| `isInstalled()`     | Local keychain / keystore | No      | `boolean`                                 |
| `getRemoteStatus()` | Helium inventory API      | Yes     | `RemoteProfileStatus` or `null` (no profile) |

Use `isInstalled()` for fast UI checks (e.g. rendering "Install" vs "Remove"). Use `getRemoteStatus()` to reconcile against the server — for example, to detect that a profile was revoked from another device.

### `CertificateInfo`

```ts
interface CertificateInfo {
  isInstalled: boolean;
  expiresAt: string | null; // ISO 8601
  subject: string | null;
  domain: string | null;
  friendlyName: string | null;
}
```

### `RemoteProfileStatus`

Returned by `getRemoteStatus()` when the server has an active profile for the subscriber.

```ts
interface RemoteProfileStatus {
  subscriberId: string;
  presetId: string;
  eapType: number;       // 13 = EAP-TLS
  expiresAt: string;     // ISO 8601
  active: boolean;       // false if the cert has expired
}
```

## Error Handling

All SDK methods throw `PasspointError` with a typed `code` property:

```ts
try {
  await install(subscriberId);
} catch (e) {
  if (e instanceof PasspointError) {
    switch (e.code) {
      case PasspointErrorCode.PERMISSION_DENIED:
        // Android: location permission not granted
        break;
      case PasspointErrorCode.PROFILE_INSTALL_CANCELLED:
        // iOS: user dismissed the OS install dialog
        break;
      case PasspointErrorCode.API_UNAUTHORIZED:
        // invalid API key
        break;
      case PasspointErrorCode.NETWORK_ERROR:
        // no internet connection
        break;
    }
  }
}
```

### Error Codes

| Code                            | Platform | Description                               |
| ------------------------------- | -------- | ----------------------------------------- |
| `NOT_CONFIGURED`                | Both     | SDK not initialized                       |
| `INVALID_CONFIG`                | Both     | Bad config (empty apiKey, etc.)           |
| `PLATFORM_NOT_SUPPORTED`        | Both     | Running on web or unsupported platform    |
| `SIMULATOR_NOT_SUPPORTED`       | iOS      | Passpoint requires a physical device      |
| `PERMISSION_DENIED`             | Android  | `ACCESS_FINE_LOCATION` not granted        |
| `MISSING_ENTITLEMENTS`          | iOS      | HotspotConfiguration capability missing   |
| `KEYPAIR_GENERATION_FAILED`     | Both     | RSA keypair generation failed             |
| `CSR_GENERATION_FAILED`         | Both     | Certificate signing request failed        |
| `NETWORK_ERROR`                 | Both     | Can't reach the Passpoint API             |
| `API_ERROR`                     | Both     | API returned an error response            |
| `API_UNAUTHORIZED`              | Both     | API key rejected (401/403)                |
| `API_RATE_LIMITED`              | Both     | Too many requests (429)                   |
| `CERTIFICATE_PARSE_FAILED`      | Both     | Couldn't parse API response certificate   |
| `CERTIFICATE_SAVE_FAILED`       | Both     | Keychain/KeyStore save failed             |
| `CERTIFICATE_NOT_FOUND`         | Both     | No cert installed (during remove)         |
| `IDENTITY_LOAD_FAILED`          | iOS      | Couldn't build TLS identity from cert+key |
| `PROFILE_INSTALL_FAILED`        | Both     | OS rejected the Passpoint profile         |
| `PROFILE_INSTALL_CANCELLED`     | iOS      | User dismissed the install dialog         |
| `PROFILE_NOT_FOUND`             | Both     | No profile to remove                      |
| `PROFILE_REMOVE_FAILED`         | Both     | Failed to remove profile                  |
| `REMOVE_FAILED`                 | Both     | Failed to remove cert and profile         |
| `WIFI_MANAGER_UNAVAILABLE`      | Android  | WifiManager service unavailable           |
| `NETWORK_SUGGESTION_DISALLOWED` | Android  | User blocked app from adding WiFi         |
| `NETWORK_SUGGESTION_LIMIT`      | Android  | Exceeded max suggestions per app          |
| `UNKNOWN`                       | Both     | Unexpected error (check `nativeError`)    |

## Configuration

### Environments

`environment` selects the Helium inventory API base URL. The SDK appends `/preset/profile/generate` and `/preset/profile/status` to it.

```ts
// Production (default) — https://api.prod.hib.nova.xyz/api/inventory/v1
{ apiKey: 'pk_xxx' }

// Development — https://api.dev.hib.nova.xyz/api/inventory/v1
{ apiKey: 'pk_xxx', environment: 'development' }

// Staging — https://api.staging.hib.nova.xyz/api/inventory/v1
{ apiKey: 'pk_xxx', environment: 'staging' }

// Custom base URL (must end at /api/inventory/v1, no trailing endpoint path)
{ apiKey: 'pk_xxx', environment: 'https://your-api.example.com/api/inventory/v1' }
```

### Custom Server CA

If you're using a custom RADIUS infrastructure with a different CA:

```ts
{
  apiKey: 'pk_xxx',
  serverCaCertPem: '-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----',
}
```

### Preset ID

If your partner account has more than one EAP-TLS preset, supply the UUID of the one you want the SDK to use:

```ts
{
  apiKey: 'pk_xxx',
  presetId: '7c9e6679-7425-40de-944b-e07fc1f90ae7',
}
```

Partners with a single preset can leave this unset.

## Requirements

- React Native >= 0.73
- iOS >= 15.0 (physical device only)
- Android API >= 26 (minSdk 26)

## License

MIT
