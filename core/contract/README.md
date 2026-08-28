# Cross-SDK contract

`contract.json` holds the values that must be byte-identical across all three
SDKs: error codes, environment base URLs, API paths and headers, EAP types, and
the HTTP status → error code mapping.

Each SDK has a conformance test that loads this file and asserts its own
constants match:

| SDK | Test |
|---|---|
| Swift | `core/swift/Tests/HeliumPasspointTests/ContractConformanceTests.swift` |
| Kotlin | `core/kotlin/src/test/kotlin/com/helium/passpoint/ContractConformanceTest.kt` |
| TypeScript | `src/__tests__/contract.test.ts` |

Adding an error code is therefore a three-line change plus this file — and if
you forget one, that platform's test fails with the exact missing symbol.

The contract is *not* code-generated. Generation would need a build step in
three toolchains to save ~80 lines of enum; assertion gives the same guarantee
for the cost of one test per platform.
