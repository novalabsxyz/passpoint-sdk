package com.helium.passpoint

/**
 * Machine-readable error codes shared by the Swift, Kotlin and TypeScript SDKs.
 *
 * The full set is defined in `core/contract/contract.json` and asserted by
 * `ContractConformanceTest`. Some codes are only ever emitted on one platform
 * ([SIMULATOR_NOT_SUPPORTED] is iOS-only, [WIFI_MANAGER_UNAVAILABLE] is
 * Android-only) but every SDK declares the complete set so partners can write
 * one `when` that compiles everywhere.
 */
enum class PasspointErrorCode {
  // Configuration
  NOT_CONFIGURED,
  INVALID_API_KEY,
  INVALID_CONFIG,

  // Platform
  PLATFORM_NOT_SUPPORTED,
  SIMULATOR_NOT_SUPPORTED,
  MISSING_ENTITLEMENTS,
  PERMISSION_DENIED,

  // Keypair / CSR
  KEYPAIR_GENERATION_FAILED,
  CSR_GENERATION_FAILED,

  // Network / API
  NETWORK_ERROR,
  API_ERROR,
  API_UNAUTHORIZED,
  API_RATE_LIMITED,

  // Certificate
  CERTIFICATE_PARSE_FAILED,
  CERTIFICATE_SAVE_FAILED,
  CERTIFICATE_NOT_FOUND,
  IDENTITY_LOAD_FAILED,

  // Profile
  PROFILE_INSTALL_FAILED,
  PROFILE_INSTALL_CANCELLED,
  PROFILE_NOT_FOUND,
  PROFILE_REMOVE_FAILED,

  // Removal
  REMOVE_FAILED,

  // Android
  WIFI_MANAGER_UNAVAILABLE,
  NETWORK_SUGGESTION_DISALLOWED,
  NETWORK_SUGGESTION_LIMIT,

  // Generic
  UNKNOWN,
}

/**
 * The only exception type thrown by the Helium Passpoint SDK.
 *
 * Switch on [code] to handle specific failures:
 * ```kotlin
 * try {
 *   client.install("sub-123")
 * } catch (e: PasspointException) {
 *   when (e.code) {
 *     PasspointErrorCode.PERMISSION_DENIED -> requestLocationPermission()
 *     PasspointErrorCode.API_UNAUTHORIZED -> reportBadApiKey()
 *     else -> log(e.message)
 *   }
 * }
 * ```
 *
 * @property code Machine-readable code, stable across SDK versions and platforms.
 */
class PasspointException(
  val code: PasspointErrorCode,
  override val message: String,
  cause: Throwable? = null,
) : Exception(message, cause)
