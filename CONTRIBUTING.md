# Contributing

This repository publishes three SDKs from one source tree, so a change often
has to land in more than one language at once. This file covers the mechanics:
what to install, what to run, and what CI will check. For *why* the repo is
laid out the way it is — the shared core, the contract, what the tests can and
cannot cover — read [ARCHITECTURE.md](ARCHITECTURE.md) first.

## Prerequisites

| Tool | Version | Needed for |
| --- | --- | --- |
| Node | 22 | TypeScript layer |
| pnpm | pinned by `packageManager` in `package.json` | ditto — run `corepack enable` and it resolves itself |
| JDK | 17 or newer | Android SDK (the build targets 17; CI uses Temurin 17) |
| Android SDK | Platform 36 | `core/kotlin` sets `compileSdk = 36` |
| Xcode | with Swift 5.9+ | iOS SDK; **macOS only** |

Set `ANDROID_HOME` to your SDK location, or write `sdk.dir` into a
`local.properties` at the repo root. That file is gitignored — it is
machine-specific and must not be committed.

You do not need all of these. The three test suites are independent, and CI
runs each on its own machine, so it is fine to contribute a TypeScript fix
without an Android SDK installed. Just say so in the PR, so a reviewer knows
which halves went unverified locally.

## Setup

```sh
pnpm install
```

That is the whole setup for the TypeScript layer. Gradle and SwiftPM resolve
their own dependencies on first build.

## The loop

```sh
pnpm lint            # biome — lints src/ only
pnpm lint:fix        # biome, applying fixes
pnpm format          # biome formatter
pnpm typescript      # tsc --noEmit
pnpm test            # jest

pnpm test:swift      # swift test — macOS slice of the Swift core
pnpm test:kotlin     # ./gradlew :passpoint-core:testDebugUnitTest
pnpm test:all        # all three
```

`swift test` runs the platform-independent half of the Swift SDK on your Mac —
CSR building, DER parsing, the API client, models, environments. `PasspointClient`
and `HotspotConfigurator` are behind `#if os(iOS)` and are only compiled, never
executed, by the test suite. See ARCHITECTURE.md → Testing for what that leaves
uncovered.

## Before opening a PR

Run what CI runs. The three jobs are independent; the commands below mirror
them exactly, so a green local run means a green PR.

```sh
# TypeScript job
pnpm lint && pnpm typescript && pnpm test

# Swift job (macOS only)
swift test
swift build --triple arm64-apple-ios15.0 --sdk "$(xcrun --sdk iphoneos --show-sdk-path)"
(cd examples/ios-swift && swift build --triple arm64-apple-ios15.0 --sdk "$(xcrun --sdk iphoneos --show-sdk-path)")
pod ipc spec HeliumPasspoint.podspec > /dev/null
ruby -c helium-passpoint-sdk.podspec > /dev/null

# Android job
./gradlew :passpoint-core:testDebugUnitTest
./gradlew :passpoint-core:assembleRelease
./gradlew :passpoint-react-native:compileDebugKotlin
./gradlew :example-android:assembleDebug
```

Two of those are easy to mistake for redundant:

- **The iOS-slice `swift build`** exists because the iOS-only half of the SDK
  has no test coverage — it needs a device keychain and entitlements. Compiling
  it is the only automated check that it still builds at all.
- **`:passpoint-react-native:compileDebugKotlin`** builds the bridge against the
  *oldest* supported React Native, pinned in `gradle.properties`. It catches a
  bridge that has drifted from the core, or a Kotlin feature newer than the
  compatibility floor allows.

The two example builds are not decoration either: both consume the SDK as a
separate module, so they fail if a symbol the public API needs stopped being
exported.

## Code style

TypeScript is formatted and linted by [Biome](https://biomejs.dev)
(`biome.json`): two-space indent, 90-column lines, double quotes, trailing
commas. `pnpm lint:fix` settles every argument. Biome only looks at `src/` —
Swift and Kotlin have no enforced formatter, so match the file you are editing.

The prevailing comment style across all three languages is to explain **why**,
not what. A comment that says a workaround exists is worth less than one that
says which platform bug forces it and what breaks if you remove it. Several
non-obvious constraints in this repo are load-bearing and documented only in
comments — read them before you delete one.

## Changing something all three SDKs share

Values the three SDKs must agree on live in
[`core/contract/contract.json`](core/contract/contract.json), and each platform
has a conformance test that asserts its own constants against that file. Adding
an error code touches five places:

1. `core/contract/contract.json` — the `errorCodes` array
2. `src/types.ts` — the `PasspointErrorCode` enum
3. `core/swift/Sources/HeliumPasspoint/PasspointError.swift` — same enum
4. `core/kotlin/src/main/kotlin/com/helium/passpoint/PasspointError.kt` — same enum
5. `README.md` — the error-code table, including whether it is thrown today or
   only declared

Miss one of the middle three and that platform's conformance test fails naming
the exact missing symbol. Miss the README and nothing fails, so check it by
hand.

One trap, described more fully in ARCHITECTURE.md → The contract instead: the
Gradle test task declares `core/contract` and `core/testdata` as inputs because
they are read at runtime through a system property. Edit the contract without
that declaration and Gradle serves the task `FROM-CACHE`, silently skipping the
one check that exists to catch that edit. If you add a new shared data file,
declare it the same way.

Test fixtures in `core/testdata/` are read by all three suites, so changing one
changes what every platform asserts against. That is the point — but it means a
fixture edit needs all three suites run, not just the one you were working in.

## Pull requests

- Branch from `main`. `main` is protected; it takes no direct pushes.
- **Squash merge only** — merge commits and rebase merges are disabled. Your PR
  title and description become the commit message on `main`, so write them for
  someone reading `git log` a year from now, not for the reviewer who already
  has the diff in front of them.
- Say what you verified and what you could not. "Android untested, no SDK
  installed" is useful; silence reads as "all green".

## Releasing

See [ARCHITECTURE.md → Releasing](ARCHITECTURE.md#releasing). One version in
`package.json` drives npm, CocoaPods, SwiftPM and Maven; one `vX.Y.Z` tag
publishes all four.

## License

Contributions are accepted under the [Apache-2.0](LICENSE) license the project
ships under.
