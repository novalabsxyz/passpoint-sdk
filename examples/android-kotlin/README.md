# Native Android example

A single-activity app driving the full SDK lifecycle: configure → install →
inspect → reconcile with the server → remove. The UI is built in code so the
example stays one file; `MainActivity.kt` is all there is.

## Build it

From the repository root:

```sh
./gradlew :example-android:assembleDebug
```

The example depends on `:passpoint-core` as a separate module, which is why CI
builds it: if anything the example needs stops being `public`, this fails.

## Run it on a device

1. Put your partner API key in `MainActivity.kt` (`apiKey`).
2. `./gradlew :example-android:installDebug` with a device attached.
3. Grant the location permission when prompted — `install()` rejects with
   `PERMISSION_DENIED` until you do.

Passpoint install works on emulators only in a limited way; use a real device
to actually associate with a hotspot.

## Notes for your own app

A real app depends on the published artifact rather than the project:

```kotlin
implementation("com.helium.passpoint:passpoint-sdk:1.0.0")
```

Two things every consuming app needs, both shown in `build.gradle.kts`:

- `minSdk 26` or higher.
- The BouncyCastle packaging excludes — without them `mergeDebugJavaResource`
  fails on duplicate OSGi metadata.

The SDK's calls block. The example uses a single-thread `Executor`; a coroutine
app should use `withContext(Dispatchers.IO)`.

## If install fails

| Error code | Usual cause |
| --- | --- |
| `PERMISSION_DENIED` | `ACCESS_FINE_LOCATION` not granted at runtime |
| `NETWORK_SUGGESTION_DISALLOWED` | User blocked the app from suggesting Wi-Fi networks in Settings |
| `NETWORK_SUGGESTION_LIMIT` | Too many suggestions registered by this app |
| `API_UNAUTHORIZED` | API key rejected |

`client.diagnostics()` returns a state dump worth attaching to a support
ticket. It never contains the API key.
