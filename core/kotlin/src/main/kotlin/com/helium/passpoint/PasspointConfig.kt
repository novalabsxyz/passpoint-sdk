package com.helium.passpoint

/** EAP authentication types supported by the SDK (IANA EAP method numbers). */
enum class EapType(val value: Int) {
  /** EAP-TLS (certificate-based). The default and the only type Helium provisions today. */
  TLS(13),

  /** EAP-TTLS (tunneled TLS). */
  TTLS(21),

  /** EAP-PEAP (Protected EAP). */
  PEAP(25);

  companion object {
    /** @throws PasspointException with [PasspointErrorCode.INVALID_CONFIG] for unknown values. */
    fun fromValue(value: Int): EapType =
      values().firstOrNull { it.value == value }
        ?: throw PasspointException(
          PasspointErrorCode.INVALID_CONFIG,
          "Unsupported EAP type: $value",
        )
  }
}

/**
 * A Helium inventory API deployment.
 *
 * Use [Custom] to point at a private deployment; the URL must end at the API
 * root (`.../api/inventory/v1`) with no trailing path.
 */
sealed class PasspointEnvironment {
  abstract val baseUrl: String

  object Production : PasspointEnvironment() {
    override val baseUrl = "https://api.prod.hib.nova.xyz/api/inventory/v1"
  }

  object Development : PasspointEnvironment() {
    override val baseUrl = "https://api-dev.dev.hib.nova.xyz/api/inventory/v1"
  }

  object Poc : PasspointEnvironment() {
    override val baseUrl = "https://api.dev.hib.nova.xyz/api/inventory/v1"
  }

  data class Custom(private val url: String) : PasspointEnvironment() {
    override val baseUrl: String = url.trimEnd('/')
  }

  companion object {
    /**
     * Resolve an environment from its string name, matching the TypeScript
     * SDK's `environment` config option. A value starting with `http` is
     * treated as a custom base URL. Unknown names fall back to [Production].
     */
    fun named(name: String): PasspointEnvironment =
      when {
        name.startsWith("http") -> Custom(name)
        name == "production" -> Production
        name == "development" -> Development
        name == "poc" -> Poc
        else -> Production
      }
  }
}

/**
 * Configuration for [PasspointClient].
 *
 * @property apiKey Partner API key issued by Helium.
 * @property environment API deployment to talk to.
 * @property eapType EAP authentication type; most partners should not change it.
 * @property serverCaCertPem Custom server CA in PEM form. When null, the CA
 *   bundled with the SDK (`res/raw/helium_server_ca.crt`) is used.
 * @property presetId Preset UUID. Required only when the partner account has
 *   more than one EAP-TLS preset configured.
 */
data class PasspointConfig(
  val apiKey: String,
  val environment: PasspointEnvironment = PasspointEnvironment.Production,
  val eapType: EapType = EapType.TLS,
  val serverCaCertPem: String? = null,
  val presetId: String? = null,
) {
  /** @throws PasspointException with [PasspointErrorCode.INVALID_CONFIG] when unusable. */
  fun validated(): PasspointConfig {
    if (apiKey.isBlank()) {
      throw PasspointException(
        PasspointErrorCode.INVALID_CONFIG,
        "apiKey is required and must be non-empty.",
      )
    }
    return this
  }

  /**
   * Android profiles are built from a certificate credential, which is EAP-TLS
   * by construction — there is nowhere to put another EAP type. iOS *can* set
   * one, so rather than silently provisioning a profile that does not match the
   * configuration, Android rejects it.
   *
   * @throws PasspointException with [PasspointErrorCode.INVALID_CONFIG].
   */
  fun requireAndroidSupported(): PasspointConfig {
    if (eapType != EapType.TLS) {
      throw PasspointException(
        PasspointErrorCode.INVALID_CONFIG,
        "Android supports EapType.TLS only; got $eapType.",
      )
    }
    return this
  }

  /**
   * Redacts the API key. A data class's generated `toString()` prints every
   * component, and configs end up in log lines and crash reports.
   */
  override fun toString(): String =
    "PasspointConfig(apiKey=<redacted>, environment=${environment.baseUrl}, " +
      "eapType=$eapType, serverCaCertPem=${if (serverCaCertPem == null) "null" else "<set>"}, " +
      "presetId=$presetId)"
}
