package com.helium.passpoint

import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/**
 * Details of the Passpoint credential currently installed on this device.
 *
 * Android keeps the issued certificate inside the system's
 * `PasspointConfiguration` and does not hand it back, so [expiresAt] and
 * [subject] are always null here. They are populated on iOS. Use
 * [PasspointClient.getRemoteStatus] when you need an authoritative expiry.
 */
data class CertificateInfo(
  /** Whether a Helium Passpoint credential is installed. */
  val isInstalled: Boolean,
  /** Client certificate expiry, or null when unavailable on this platform. */
  val expiresAt: Instant? = null,
  /** Client certificate subject CN, or null when unavailable on this platform. */
  val subject: String? = null,
  /** Passpoint domain (HomeSP FQDN) of the installed profile. */
  val domain: String? = null,
  /** Human-readable profile name. */
  val friendlyName: String? = null,
) {
  companion object {
    /** The "nothing installed" value. */
    val NOT_INSTALLED = CertificateInfo(isInstalled = false)
  }
}

/** The server's view of a subscriber's profile, from `GET /preset/profile/status`. */
data class RemoteProfileStatus(
  /** Subscriber identifier the certificate was issued to. */
  val subscriberId: String,
  /** UUID of the preset used to issue the certificate. */
  val presetId: String,
  /** IANA EAP method number (13 = EAP-TLS). */
  val eapType: Int,
  /**
   * Certificate expiry, or null when the server sent a timestamp this SDK
   * cannot parse. [expiresAtRaw] always carries the server's exact string, so
   * an unrecognised format degrades rather than failing the call.
   */
  val expiresAt: Instant?,
  /** The `expires_at` string exactly as the server sent it. */
  val expiresAtRaw: String,
  /** Whether the certificate has not yet expired. */
  val active: Boolean,
)

/** A profile issued by the inventory API in response to a CSR. */
internal data class IssuedProfile(
  val friendlyName: String,
  val domainName: String,
  val naiRealmNames: List<String>,
  val trustedServerNames: List<String>,
  val tlsVersion: String,
  val certificate: String,
  val caChain: List<String>,
)

/**
 * Date handling shared by the API client and the React Native bridge.
 *
 * The inventory API emits RFC 3339 timestamps, sometimes with fractional
 * seconds and sometimes with a numeric offset instead of `Z`. Parsing accepts
 * all of those; formatting always produces the canonical second-precision UTC
 * form, byte-identical to what the Swift SDK emits.
 */
internal object Iso8601 {
  private val FORMATTER: DateTimeFormatter =
    DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss'Z'").withZone(ZoneOffset.UTC)

  fun parse(value: String): Instant? {
    val normalized = normalize(value)
    return try {
      OffsetDateTime.parse(normalized).toInstant()
    } catch (_: Exception) {
      try {
        Instant.parse(normalized)
      } catch (_: Exception) {
        null
      }
    }
  }

  /**
   * Widen what the strict RFC 3339 parsers accept, so the Kotlin and Swift SDKs
   * agree on which server timestamps are parseable. The rules are mirrored
   * exactly in `ISO8601.normalize` on the Swift side, and the same table of
   * inputs is asserted in both suites.
   *
   * 1. surrounding whitespace is ignored
   * 2. the `t` separator and `z` designator may be lower case
   * 3. a numeric offset may omit the colon (`+0100`)
   * 4. seconds may be omitted (`2035-01-01T00:00Z`)
   */
  fun normalize(value: String): String {
    var result = value.trim().uppercase()

    // "+0100" / "-0530" -> "+01:00" / "-05:30"
    if (result.length >= 5) {
      val tail = result.substring(result.length - 5)
      if ((tail[0] == '+' || tail[0] == '-') && tail.drop(1).all { it.isDigit() }) {
        result = result.dropLast(5) + "${tail[0]}${tail.substring(1, 3)}:${tail.substring(3)}"
      }
    }

    // "2035-01-01T00:00Z" -> "2035-01-01T00:00:00Z"
    val tIndex = result.indexOf('T')
    if (tIndex >= 0) {
      val clock = result.substring(tIndex + 1).takeWhile { it.isDigit() || it == ':' }
      if (clock.count { it == ':' } == 1) {
        val insertAt = tIndex + 1 + clock.length
        result = result.substring(0, insertAt) + ":00" + result.substring(insertAt)
      }
    }

    return result
  }

  fun format(instant: Instant): String = FORMATTER.format(instant)
}
