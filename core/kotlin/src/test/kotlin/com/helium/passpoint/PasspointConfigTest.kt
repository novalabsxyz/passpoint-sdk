package com.helium.passpoint

import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.Test

class PasspointConfigTest {

  // region Environment

  @Test
  fun `named environments resolve`() {
    assertEquals(PasspointEnvironment.Production, PasspointEnvironment.named("production"))
    assertEquals(PasspointEnvironment.Development, PasspointEnvironment.named("development"))
    assertEquals(PasspointEnvironment.Poc, PasspointEnvironment.named("poc"))
  }

  /** Matches the TypeScript SDK, which also falls back rather than throwing. */
  @Test
  fun `unknown name falls back to production`() {
    assertEquals(PasspointEnvironment.Production, PasspointEnvironment.named("staging"))
    assertEquals(PasspointEnvironment.Production, PasspointEnvironment.named(""))
  }

  @Test
  fun `http prefix is treated as a custom base url`() {
    assertEquals(
      "https://api.internal.test/api/inventory/v1",
      PasspointEnvironment.named("https://api.internal.test/api/inventory/v1").baseUrl,
    )
  }

  @Test
  fun `custom base url loses trailing slashes`() {
    assertEquals(
      "https://api.internal.test/v1",
      PasspointEnvironment.named("https://api.internal.test/v1///").baseUrl,
    )
    assertEquals(
      "https://api.internal.test/v1",
      PasspointEnvironment.Custom("https://api.internal.test/v1/").baseUrl,
    )
  }

  // endregion

  // region Defaults and validation

  @Test
  fun `defaults`() {
    val config = PasspointConfig(apiKey = "key")
    assertEquals(PasspointEnvironment.Production, config.environment)
    assertEquals(EapType.TLS, config.eapType)
    assertNull(config.serverCaCertPem)
    assertNull(config.presetId)
  }

  @Test
  fun `validation accepts a non-empty key`() {
    assertNotNull(PasspointConfig(apiKey = "key").validated())
  }

  @Test
  fun `validation rejects a blank key`() {
    for (key in listOf("", "   ", "\n\t")) {
      assertThrowsPasspoint(PasspointErrorCode.INVALID_CONFIG) {
        PasspointConfig(apiKey = key).validated()
      }
    }
  }

  @Test
  fun `eap type resolves from its iana number`() {
    assertEquals(EapType.TLS, EapType.fromValue(13))
    assertEquals(EapType.TTLS, EapType.fromValue(21))
    assertEquals(EapType.PEAP, EapType.fromValue(25))
    assertThrowsPasspoint(PasspointErrorCode.INVALID_CONFIG) { EapType.fromValue(99) }
  }

  // endregion

  // region ISO 8601 — must agree byte-for-byte with the Swift SDK

  @Test
  fun `parses timestamps without fractional seconds`() {
    assertEquals(
      "2035-01-01T00:00:00Z",
      Iso8601.format(assertNotNull(Iso8601.parse("2035-01-01T00:00:00Z"))),
    )
  }

  @Test
  fun `parses timestamps with fractional seconds`() {
    assertEquals(
      "2035-01-01T00:00:00Z",
      Iso8601.format(assertNotNull(Iso8601.parse("2035-01-01T00:00:00.500Z"))),
    )
  }

  @Test
  fun `parses timestamps with a numeric offset`() {
    assertEquals(
      "2035-01-01T00:00:00Z",
      Iso8601.format(assertNotNull(Iso8601.parse("2035-01-01T01:00:00+01:00"))),
    )
  }

  @Test
  fun `rejects nonsense`() {
    assertNull(Iso8601.parse("whenever"))
    assertNull(Iso8601.parse(""))
  }

  @Test
  fun `format is stable across a round trip`() {
    val original = "2035-01-01T00:00:00Z"
    assertEquals(original, Iso8601.format(assertNotNull(Iso8601.parse(original))))
  }

  @Test
  fun `format truncates rather than rounds`() {
    assertEquals(
      "2035-01-01T00:00:00Z",
      Iso8601.format(Instant.parse("2035-01-01T00:00:00.999Z")),
    )
  }

  // endregion

  // region ISO 8601 acceptance parity

  /**
   * The same table is asserted in the Swift suite
   * (`testAcceptsTheSameTimestampsAsTheAndroidSDK`). Both SDKs must agree on
   * which server timestamps parse and what they parse to, or `expiresAt`
   * silently differs by platform.
   */
  @Test
  fun `accepts the same timestamps as the iOS SDK`() {
    val accepted = listOf(
      "2035-01-01T00:00:00Z" to "2035-01-01T00:00:00Z",
      "2035-01-01T00:00:00.500Z" to "2035-01-01T00:00:00Z",
      "2035-01-01T00:00:00.123456Z" to "2035-01-01T00:00:00Z",
      "2035-01-01T01:00:00+01:00" to "2035-01-01T00:00:00Z",
      "2035-01-01T01:00:00+0100" to "2035-01-01T00:00:00Z",
      "2035-01-01T00:00Z" to "2035-01-01T00:00:00Z",
      "2035-01-01t00:00:00z" to "2035-01-01T00:00:00Z",
      "  2035-01-01T00:00:00Z  " to "2035-01-01T00:00:00Z",
      "1969-07-20T20:17:00Z" to "1969-07-20T20:17:00Z",
    )
    for ((input, expected) in accepted) {
      assertEquals(expected, Iso8601.format(assertNotNull(Iso8601.parse(input), "parsing $input")))
    }

    for (input in listOf("whenever", "", "2035-13-01T00:00:00Z", "2035-01-01")) {
      assertNull(Iso8601.parse(input), "should not parse $input")
    }
  }

  @Test
  fun `normalize is idempotent`() {
    for (input in listOf("2035-01-01T00:00:00Z", "2035-01-01t00:00z", "2035-01-01T01:00:00+0100")) {
      val once = Iso8601.normalize(input)
      assertEquals(once, Iso8601.normalize(once), "normalizing $input twice")
    }
  }

  // endregion

  // region Android EAP-type restriction

  /**
   * Android profiles are built from a certificate credential, so there is
   * nowhere to put a non-TLS EAP type. Rejecting is better than the previous
   * behaviour, which accepted the value and silently ignored it.
   */
  @Test
  fun `android rejects a non-TLS eap type instead of ignoring it`() {
    assertNotNull(PasspointConfig(apiKey = "k", eapType = EapType.TLS).requireAndroidSupported())
    for (eapType in listOf(EapType.TTLS, EapType.PEAP)) {
      assertThrowsPasspoint(PasspointErrorCode.INVALID_CONFIG) {
        PasspointConfig(apiKey = "k", eapType = eapType).requireAndroidSupported()
      }
    }
  }

  // endregion

  // region Secret hygiene

  /** A data class prints every component; configs reach logs and crash reports. */
  @Test
  fun `toString does not leak the api key`() {
    val config = PasspointConfig(apiKey = "super-secret-key", presetId = "preset-1")
    val text = config.toString()
    assertFalse(text.contains("super-secret-key"), "was: $text")
    assertTrue(text.contains("<redacted>"))
    assertTrue(text.contains("preset-1"), "non-secret fields should still be visible")
  }

  @Test
  fun `toString marks a custom server ca as set without printing it`() {
    val text = PasspointConfig(apiKey = "k", serverCaCertPem = "-----BEGIN CERTIFICATE-----x").toString()
    assertFalse(text.contains("BEGIN CERTIFICATE"))
    assertTrue(text.contains("<set>"))
  }

  // endregion
}
