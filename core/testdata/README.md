# Shared test fixtures

Read by all three test suites so the Swift, Kotlin and TypeScript SDKs are
exercised against byte-identical inputs.

| File | Used for |
|---|---|
| `profile-response.json` | A valid `POST /preset/profile/generate` response |
| `status-response.json` | A valid `GET /preset/profile/status` response |
| `testLeaf.crt` | Self-signed leaf, `notAfter` encoded as **UTCTime** (2035-01-01T00:00:00Z), CN `anonymous@subscriber-42.helium.example` |
| `testLeafGeneralized.crt` | Self-signed leaf, `notAfter` encoded as **GeneralizedTime** (2060-01-01T00:00:00Z), CN `anonymous@subscriber-99.helium.example` |
| `testLeafNoRealm.crt` | Self-signed leaf whose CN (`plain-common-name`) has no `@`, for the realm-derivation fallback |

X.509 switches from UTCTime to GeneralizedTime at year 2050, and the iOS SDK
parses that field out of the raw DER, so both encodings need a fixture.

The certificates carry no private key and are not trusted by anything. They
expire in 2035 and 2060; nothing here needs regenerating before then.

Each suite resolves this directory deterministically rather than by walking
relative paths from a working directory:

- **Swift** — from `#filePath` of the test source (`TestFixtures.swift`)
- **Kotlin** — from the `repoRoot` system property set in `core/kotlin/build.gradle.kts`
- **TypeScript** — from `__dirname` of the test file
