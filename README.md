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

function WifiScreen({ userId }) {
  const { isInstalled, install, remove, isLoading, error } = usePasspoint();

  const handleInstall = async () => {
    try {
      await install(userId);
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

## API Reference

### `<PasspointProvider config={...}>`

Initializes the SDK. Wrap your app (or relevant subtree) in this provider.

```ts
interface PasspointConfig {
  apiKey: string; // required
  environment?: string; // 'production' (default) | 'staging' | 'development' | custom URL
  eapType?: EapType; // EapType.TLS (default) | EapType.TTLS | EapType.PEAP
  serverCaCertPem?: string; // custom CA cert PEM (optional, uses bundled ISRG Root X1)
  keychainAccessGroup?: string; // iOS only: '<TEAM_ID>.com.apple.networkextensionsharing'
}
```

### `usePasspoint()`

React hook for all passpoint operations. Must be inside `<PasspointProvider>`.

```ts
interface UsePasspointResult {
  isInstalled: boolean | null; // null while loading
  certificateInfo: CertificateInfo | null;
  install: (userId: string) => Promise<InstallResult>;
  remove: () => Promise<RemoveResult>;
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
await sdk.install("user-123");
await sdk.isInstalled();
await sdk.getCertificateInfo();
await sdk.remove();
```

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

## Error Handling

All SDK methods throw `PasspointError` with a typed `code` property:

```ts
try {
  await install(userId);
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

```ts
// Production (default)
{ apiKey: 'pk_xxx' }

// Development
{ apiKey: 'pk_xxx', environment: 'development' }

// Staging
{ apiKey: 'pk_xxx', environment: 'staging' }

// Custom endpoint
{ apiKey: 'pk_xxx', environment: 'https://your-api.example.com/passpoint/generate' }
```

### Custom Server CA

If you're using a custom RADIUS infrastructure with a different CA:

```ts
{
  apiKey: 'pk_xxx',
  serverCaCertPem: '-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----',
}
```

## Requirements

- React Native >= 0.73
- iOS >= 15.0 (physical device only)
- Android API >= 26 (minSdk 26)

## License

MIT
