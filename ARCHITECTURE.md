# Architecture

One repository, three published SDKs, one implementation each for iOS and
Android. The React Native package is a bridge over the same code the native
packages expose directly — there is no second implementation of anything.

## Layout

```
passpoint-sdk/
├── Package.swift                 SwiftPM manifest (must be at the repo root)
├── HeliumPasspoint.podspec       Native CocoaPods pod → core/swift only
├── helium-passpoint-sdk.podspec  React Native pod → core/swift + ios/
├── settings.gradle.kts           Gradle build for THIS repo (not host apps)
├── package.json                  npm package @helium/passpoint-sdk
│
├── core/
│   ├── contract/contract.json    Values all three SDKs must agree on
│   ├── testdata/                 Fixtures all three test suites read
│   ├── swift/                    The iOS SDK
│   │   ├── Sources/HeliumPasspoint/
│   │   └── Tests/HeliumPasspointTests/
│   └── kotlin/                   The Android SDK
│       ├── build.gradle.kts      Publishes com.helium.passpoint:passpoint-sdk
│       └── src/{main,test}/
│
├── src/                          TypeScript layer (npm)
├── ios/                          React Native bridge only (2 files)
├── android/                      React Native bridge only (2 files)
└── examples/{react-native,ios-swift,android-kotlin}/
```

## What is shared, and how

| Boundary | Mechanism | Why |
| --- | --- | --- |
| Swift core → SwiftPM | Root `Package.swift`, target `path:` into `core/swift` | SwiftPM resolves a package from the repository root only; there is no subdirectory support. Targets can point anywhere. |
| Swift core → native CocoaPods | `HeliumPasspoint.podspec` | For iOS apps not on SwiftPM. |
| Swift core → React Native | `helium-passpoint-sdk.podspec` lists both `core/swift/**` and `ios/**` in `source_files` | Compiles core and bridge into one module, so the bridge needs no `import HeliumPasspoint` and can use the core's internal `ISO8601` helper. |
| Kotlin core → Maven | `core/kotlin/build.gradle.kts` with `maven-publish` | The AAR native apps depend on. |
| Kotlin core → React Native | `android/build.gradle` adds `../core/kotlin/src/main/kotlin` to `java.srcDirs` and `../core/kotlin/src/main/res` to `res.srcDirs` | Autolinking injects `android/` into the *host app's* Gradle build, which knows nothing about this repo's `settings.gradle.kts` — a `project(...)` dependency cannot resolve. A Maven coordinate would force a publish per change and add a repository requirement for partners. |
| Error codes, env URLs, API paths | `core/contract/contract.json` + a conformance test per platform | See below. |
| Test inputs | `core/testdata/` | All three suites assert against identical bytes. |

### Why not Kotlin Multiplatform or a Rust core

The duplicated logic between Swift and Kotlin is roughly 80 lines each of HTTP
plus JSON models. Everything else is irreducibly platform-specific: Keychain vs
KeyStore, `NEHotspotConfiguration` vs `PasspointConfiguration`, `SecKey` vs
BouncyCastle. A shared-core toolchain would add a build step to three
pipelines to deduplicate 160 lines.

### The contract instead

`core/contract/contract.json` holds every value the three SDKs must agree on —
error codes, environment base URLs, API paths and headers, EAP types, the CSR
common-name template, and the HTTP-status-to-error-code mapping. Each SDK has a
conformance test that loads the file and asserts its own constants match:

- `core/swift/Tests/HeliumPasspointTests/ContractConformanceTests.swift`
- `core/kotlin/src/test/kotlin/com/helium/passpoint/ContractConformanceTest.kt`
- `src/__tests__/contract.test.ts`

Adding an error code is a three-line change plus the contract, and forgetting
one fails that platform's build naming the exact missing symbol. Code
generation would give the same guarantee for the cost of a generator in three
toolchains; assertion is cheaper and the failure message is better.

Two things this only works if you keep true:

- **Every key must be asserted, and every loop over the contract must be
  bounded.** A test that iterates whatever keys happen to be in the file lets
  the contract shrink to nothing while staying green; the mapping tests assert
  the expected key set first.
- **The Gradle test task declares `core/contract` and `core/testdata` as
  inputs** (`core/kotlin/build.gradle.kts`). They are read at runtime via the
  `repoRoot` system property, so without that declaration Gradle serves the
  task `FROM-CACHE` when only the contract changed — silently skipping the one
  check that exists to catch exactly that edit.

## Testing

```sh
pnpm test:all          # all three suites
pnpm test              # TypeScript (jest)
pnpm test:swift        # swift test — runs on macOS
pnpm test:kotlin       # ./gradlew :passpoint-core:testDebugUnitTest
```

The Swift package declares a macOS platform purely so `swift test` can run the
platform-independent half of the SDK on a Mac. `PasspointClient` and
`HotspotConfigurator` are behind `#if os(iOS)`; everything else — the CSR
builder, DER reader, API client, models, environments — is cross-platform and
covered.

What the suites cover, and what they cannot:

| Area | Covered by | Notes |
| --- | --- | --- |
| CSR generation | Swift + Kotlin | Real RSA keys, signature re-verified. The Swift suite also cross-checks with `openssl req -verify` — asserting on the *output text*, because macOS's `/usr/bin/openssl` is LibreSSL and exits 0 even on `verify failure`. A companion test feeds it a tampered signature to prove the cross-check can fail. |
| DER writing | Swift | Length and integer edge cases the 2048-bit happy path never reaches |
| X.509 `notAfter` parsing | Swift + Kotlin | UTCTime and GeneralizedTime fixtures, plus truncation fuzzing on the iOS DER reader |
| API client | Swift + Kotlin | Stub transport: request shape, every status mapping, malformed bodies |
| Environments, config, ISO 8601 | All three | Including that Swift and Kotlin emit byte-identical timestamps |
| Contract conformance | All three | |
| Keychain / KeyStore | **Not covered** | Requires a device keychain; unit tests deliberately never touch the developer's |
| `NEHotspotConfigurationManager` / `WifiManager` | **Not covered** | Requires a physical device with entitlements |
| Public API completeness | `examples/ios-swift`, `examples/android-kotlin` | Both consume the SDK as a separate module, so they fail to build if anything needed is not exported. Strong on Swift, where the default is `internal`; weaker on Kotlin, where it is `public`. |
| Bridge JSON schema | **Not covered** | `ios/HeliumPasspointSDK.swift`, `android/…/PasspointSDKModule.kt` and `src/types.ts` hand-duplicate the key names. They match today, but a rename on one side fails nothing — the TypeScript tests mock the bridge and the native suites stop at the core. |

The device-only paths are exactly the ones `PasspointClient.diagnostics()`
exists to debug.

## Known gaps

What is left, and why.

| | Impact |
| --- | --- |
| **Android AAA server-*name* pinning is best-effort.** `aaaServerTrustedNames` and `setCheckAaaServerCertStatus` are `@hide` with no public setter, so they are set reflectively and the hidden-API blocklist can make them no-op on API 28+. The server's certificate *chain* is still validated against the Helium root CA via the public `Credential.setCaCertificate`, which is always set — what can be lost is name pinning and OCSP. Both outcomes are now recorded and surfaced in `diagnostics()` as `aaaServerTrustedNames` / `aaaServerCertStatusCheck` rather than swallowed. Closing it fully needs a platform API that does not exist. | Security-relevant asymmetry with iOS |
| **New Architecture is untested.** The bridge is a legacy `NativeModules` / `RCT_EXTERN_MODULE` pair with no codegen config. It should work through interop on RN 0.76+, but nothing verifies it. | Unknown |
| **No host-app build in CI.** The Gradle jobs build a library, so `mergeReleaseJavaResource` never runs and the BouncyCastle packaging clash cannot regress-test itself. A minified React-Native-shaped host app in CI would close this. | Medium |
| **Keychain and `WifiManager` paths have no automated coverage.** They need a physical device with entitlements. `diagnostics()` exists for exactly these. | Medium |

### Closed

Each of these was a real defect inherited from before the split.

| | Fix |
| --- | --- |
| iOS `deleteAll()` deleted **every** certificate in the keychain access group — including other NetworkExtension components' — because the required group is shared | `KeychainManager.deleteSDKCertificates()` enumerates and deletes by the SDK's own `HeliumPasspoint` label prefix. `KeychainManagerTests` pins the labelling invariant that makes this safe, including the historical label formats so upgrades still clean up. |
| Android `removeAll()` deleted every network suggestion the host app had registered | Suggestions are matched by the Passpoint FQDN recorded at install; the no-FQDN fallback is still narrowed to suggestions carrying a Passpoint config. |
| Android stored the RSA private key in backup-eligible SharedPreferences, so it rode Auto Backup onto other devices | Moved to `Context.getNoBackupFilesDir()`, which the platform excludes from backup and device-to-device transfer with no host-app manifest change. Keys written by older versions are migrated and erased from prefs on first use. |
| `eapType` was accepted and silently ignored on Android | `PasspointConfig.requireAndroidSupported()` rejects non-TLS with `INVALID_CONFIG`. |
| An unknown `tls_version` threw `PROFILE_INSTALL_FAILED` on iOS, so a future `"1.3"` from the API would break iOS while Android kept working | `TLSVersionPreference.from` falls back to 1.2; `preferredTLSVersion` is a preference the OS negotiates upward from anyway. |
| Swift and Kotlin accepted different ISO 8601 spellings | A shared normalisation step (lower-case `t`/`z`, colon-less offsets, omitted seconds), asserted from an identical table in both suites. |
| `PasspointClient` had unsynchronised mutable state; concurrent `install`/`remove` could race, and `.shared` was rejected under Swift 6 | State behind a lock on both platforms, `install`/`remove` serialised (`SerialGate` on Swift, `ReentrantLock` on Kotlin), read-only queries left ungated. Builds clean with `-strict-concurrency=complete`. |
| `PasspointConfig`'s generated `toString()`/description printed the API key into logs and crash reports | Custom description redacting `apiKey` and the CA PEM on both platforms. |

## Build verification

`./gradlew build` also compiles two things that are not published from here:

- `:passpoint-react-native` — the bridge in `android/`, against the oldest
  supported React Native (pinned in `gradle.properties`, so its Kotlin version
  and the SDK's stay compatible). Host apps resolve `+` instead.
- `:example-android` — proves the public Kotlin API is usable from outside the
  library module.

The iOS equivalents are `swift build` (SDK, macOS and iOS slices) and
`cd examples/ios-swift && swift build --triple arm64-apple-ios15.0`.

## Releasing

One git tag drives all three registries; keep `package.json`'s `version` as the
source of truth (both podspecs and the Maven publication read it).

1. Bump `version` in `package.json`.
2. Tag **`vX.Y.Z`** and push. SwiftPM accepts the tag with or without the `v`;
   CocoaPods does not guess, so both podspecs pin `:tag => "v#{s.version}"`. If
   you ever switch to bare tags, change the podspecs in the same commit.
3. `pnpm publish` for npm.
4. `./gradlew :passpoint-core:publishAllPublicationsToSonatypeRepository`
   with `MAVEN_USERNAME` / `MAVEN_PASSWORD` set (or `-PheliumMavenUser=…
   -PheliumMavenPassword=…`, and `-PheliumMavenUrl=…` to target somewhere else).

### Before the first Maven release

Two prerequisites, both external and both slow:

- **A verified namespace** for `com.helium.passpoint` — Sonatype requires proof
  of domain ownership. This is the long pole; start it early.
- **GPG signing.** Maven Central rejects unsigned artifacts. The
  `signing` plugin is deliberately *not* wired up yet because it needs a real
  key; add it alongside the namespace approval.

Until both are done, `publishToMavenLocal` is the only publication that works.
