package com.helium.passpoint

import java.io.IOException
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.json.JSONObject
import org.junit.Test

class ProfileApiClientTest {
  private val baseUrl = "https://api.example.test/api/inventory/v1"
  private val apiKey = "test-api-key"

  private fun client(transport: HttpTransport) = ProfileApiClient(baseUrl, apiKey, transport)

  private fun bodyJson(request: HttpRequest?): JSONObject =
    JSONObject(String(assertNotNull(request?.body), Charsets.UTF_8))

  // region generateProfile

  @Test
  fun `decodes the profile response`() {
    val transport = FakeTransport(200, Fixtures.text("profile-response.json"))
    val profile = client(transport)
      .generateProfile("csr", "subscriber-42", EapType.TLS, presetId = null)

    assertEquals("Helium WiFi", profile.friendlyName)
    assertEquals("helium.example", profile.domainName)
    assertEquals(listOf("helium.example", "roaming.helium.example"), profile.naiRealmNames)
    assertEquals(listOf("radius.helium.example"), profile.trustedServerNames)
    assertEquals("1.2", profile.tlsVersion)
    assertTrue(profile.certificate.contains("BEGIN CERTIFICATE"))
    assertEquals(1, profile.caChain.size)
  }

  @Test
  fun `sends the expected generate request`() {
    val transport = FakeTransport(200, Fixtures.text("profile-response.json"))
    client(transport).generateProfile("the-csr", "subscriber-42", EapType.TLS, presetId = null)

    val request = assertNotNull(transport.lastRequest)
    assertEquals("POST", request.method)
    assertEquals("$baseUrl/preset/profile/generate", request.url)
    assertEquals(apiKey, request.headers["X-Helium-P-Api-Key"])
    assertEquals("application/json", request.headers["Content-Type"])

    val body = bodyJson(request)
    assertEquals(13, body.getInt("type"))
    assertEquals("subscriber-42", body.getString("subscriber_id"))
    assertEquals("the-csr", body.getString("csr"))
    assertFalse(body.has("preset_id"), "preset_id must be omitted when unset")
  }

  @Test
  fun `includes preset id when set`() {
    val transport = FakeTransport(200, Fixtures.text("profile-response.json"))
    client(transport).generateProfile("csr", "s", EapType.TLS, presetId = "preset-uuid")
    assertEquals("preset-uuid", bodyJson(transport.lastRequest).getString("preset_id"))
  }

  @Test
  fun `omits blank preset id`() {
    val transport = FakeTransport(200, Fixtures.text("profile-response.json"))
    client(transport).generateProfile("csr", "s", EapType.TLS, presetId = "   ")
    assertFalse(bodyJson(transport.lastRequest).has("preset_id"))
  }

  @Test
  fun `sends the configured eap type`() {
    val transport = FakeTransport(200, Fixtures.text("profile-response.json"))
    client(transport).generateProfile("csr", "s", EapType.TTLS, presetId = null)
    assertEquals(21, bodyJson(transport.lastRequest).getInt("type"))
  }

  @Test
  fun `defaults a missing tls version`() {
    val body = """
      {"friendly_name":"n","domain_name":"d","nai_realm_names":[],
       "trusted_server_names":[],"certificate":"c","ca_chain":[]}
    """.trimIndent()
    val profile = client(FakeTransport(200, body))
      .generateProfile("csr", "s", EapType.TLS, presetId = null)
    assertEquals("1.2", profile.tlsVersion)
  }

  @Test
  fun `rejects malformed json`() {
    assertThrowsPasspoint(PasspointErrorCode.API_ERROR) {
      client(FakeTransport(200, "{not json"))
        .generateProfile("csr", "s", EapType.TLS, presetId = null)
    }
  }

  @Test
  fun `rejects a missing field`() {
    assertThrowsPasspoint(PasspointErrorCode.API_ERROR) {
      client(FakeTransport(200, """{"friendly_name":"n"}"""))
        .generateProfile("csr", "s", EapType.TLS, presetId = null)
    }
  }

  /** 404 is only meaningful on the status endpoint; here it is a plain error. */
  @Test
  fun `treats 404 on generate as an error`() {
    assertThrowsPasspoint(PasspointErrorCode.API_ERROR) {
      client(FakeTransport(404, "")).generateProfile("csr", "s", EapType.TLS, presetId = null)
    }
  }

  // endregion

  // region Status mapping (contract.json httpStatusMapping)

  @Test
  fun `status codes map to contract error codes`() {
    val cases = listOf(
      400 to PasspointErrorCode.API_ERROR,
      401 to PasspointErrorCode.API_UNAUTHORIZED,
      403 to PasspointErrorCode.API_UNAUTHORIZED,
      429 to PasspointErrorCode.API_RATE_LIMITED,
      500 to PasspointErrorCode.API_ERROR,
      503 to PasspointErrorCode.API_ERROR,
    )
    for ((status, expected) in cases) {
      assertThrowsPasspoint(expected) {
        client(FakeTransport(status, "boom"))
          .generateProfile("csr", "s", EapType.TLS, presetId = null)
      }
    }
  }

  @Test
  fun `transport failure becomes a network error`() {
    assertThrowsPasspoint(PasspointErrorCode.NETWORK_ERROR) {
      client(FakeTransport(IOException("offline")))
        .generateProfile("csr", "s", EapType.TLS, presetId = null)
    }
  }

  // endregion

  // region profileStatus

  @Test
  fun `decodes the status response`() {
    val transport = FakeTransport(200, Fixtures.text("status-response.json"))
    val status = assertNotNull(client(transport).profileStatus("subscriber-42"))

    assertEquals("subscriber-42", status.subscriberId)
    assertEquals("0f9d2b1e-4c3a-4f7b-9d21-6a8c5e0b1234", status.presetId)
    assertEquals(13, status.eapType)
    assertEquals(Instant.parse("2035-01-01T00:00:00Z"), status.expiresAt)
    assertEquals("2035-01-01T00:00:00Z", status.expiresAtRaw)
    assertTrue(status.active)
  }

  @Test
  fun `sends the expected status request`() {
    val transport = FakeTransport(200, Fixtures.text("status-response.json"))
    client(transport).profileStatus("subscriber-42")

    val request = assertNotNull(transport.lastRequest)
    assertEquals("GET", request.method)
    assertEquals("$baseUrl/preset/profile/status?subscriber_id=subscriber-42", request.url)
    assertEquals(apiKey, request.headers["X-Helium-P-Api-Key"])
    assertNull(request.body)
  }

  /**
   * URLEncoder is form-encoding and emits `+` for a space, which a server
   * reading the query string decodes back only by convention. These
   * expectations are duplicated verbatim in the Swift suite
   * (`testProfileStatusPercentEncodesTheSubscriberID`) so the two agree.
   */
  @Test
  fun `builds the same status url as the iOS SDK`() {
    val cases = listOf(
      "user+1@example.com" to "user%2B1%40example.com",
      "has space" to "has%20space",
      "plain-123" to "plain-123",
      "sl/ash&amp" to "sl%2Fash%26amp",
      "unicode-\u00C4" to "unicode-%C3%84",
      "tilde~dot." to "tilde~dot.",
    )
    for ((subscriberId, expected) in cases) {
      val transport = FakeTransport(200, Fixtures.text("status-response.json"))
      client(transport).profileStatus(subscriberId)
      assertEquals(
        "$baseUrl/preset/profile/status?subscriber_id=$expected",
        assertNotNull(transport.lastRequest).url,
        "encoding of $subscriberId",
      )
    }
  }

  /** 404 means "the server has no profile for this subscriber", not a failure. */
  @Test
  fun `returns null on 404`() {
    assertNull(client(FakeTransport(404, """{"detail":"not found"}""")).profileStatus("nobody"))
  }

  @Test
  fun `status unauthorized`() {
    assertThrowsPasspoint(PasspointErrorCode.API_UNAUTHORIZED) {
      client(FakeTransport(401, "")).profileStatus("s")
    }
  }

  @Test
  fun `status rate limited`() {
    assertThrowsPasspoint(PasspointErrorCode.API_RATE_LIMITED) {
      client(FakeTransport(429, "")).profileStatus("s")
    }
  }

  /**
   * An unrecognised timestamp must not fail the call: the raw string still
   * reaches the caller, and `active` is what callers branch on. The React
   * Native bridge forwards `expiresAtRaw` verbatim, so a server format this SDK
   * cannot parse behaves exactly as it did before the native split.
   */
  @Test
  fun `keeps an unparseable expiry as raw`() {
    val body = """
      {"subscriber_id":"s","preset_id":"p","eap_type":13,
       "expires_at":"2027-08-06 12:34:56+00","active":true}
    """.trimIndent()
    val status = assertNotNull(client(FakeTransport(200, body)).profileStatus("s"))
    assertNull(status.expiresAt)
    assertEquals("2027-08-06 12:34:56+00", status.expiresAtRaw)
    assertTrue(status.active)
  }

  @Test
  fun `preserves the servers exact timestamp`() {
    for (raw in listOf(
      "2035-01-01T00:00:00Z",
      "2035-01-01T00:00:00.123456Z",
      "2035-01-01T01:00:00+01:00",
      "not a date at all",
    )) {
      val body = """
        {"subscriber_id":"s","preset_id":"p","eap_type":13,
         "expires_at":"$raw","active":true}
      """.trimIndent()
      assertEquals(raw, assertNotNull(client(FakeTransport(200, body)).profileStatus("s")).expiresAtRaw)
    }
  }

  @Test
  fun `rejects a missing expiry`() {
    val body = """{"subscriber_id":"s","preset_id":"p","eap_type":13,"active":true}"""
    assertThrowsPasspoint(PasspointErrorCode.API_ERROR) {
      client(FakeTransport(200, body)).profileStatus("s")
    }
  }

  /** A null entry in a string array must not abort the install. */
  @Test
  fun `tolerates a null entry in a string array`() {
    val body = """
      {"friendly_name":"n","domain_name":"d","nai_realm_names":[null,"r"],
       "trusted_server_names":[],"tls_version":"1.2","certificate":"c","ca_chain":[]}
    """.trimIndent()
    val profile = client(FakeTransport(200, body))
      .generateProfile("csr", "s", EapType.TLS, presetId = null)
    assertEquals(2, profile.naiRealmNames.size)
    assertEquals("r", profile.naiRealmNames[1])
  }

  @Test
  fun `accepts fractional seconds`() {
    val body = """
      {"subscriber_id":"s","preset_id":"p","eap_type":13,
       "expires_at":"2035-01-01T00:00:00.123Z","active":false}
    """.trimIndent()
    val status = assertNotNull(client(FakeTransport(200, body)).profileStatus("s"))
    assertEquals("2035-01-01T00:00:00Z", Iso8601.format(assertNotNull(status.expiresAt)))
    assertEquals("2035-01-01T00:00:00.123Z", status.expiresAtRaw, "raw is passed through unchanged")
    assertFalse(status.active)
  }

  @Test
  fun `trailing slashes on the base url do not double up`() {
    val transport = FakeTransport(200, Fixtures.text("status-response.json"))
    ProfileApiClient("$baseUrl///", apiKey, transport).profileStatus("s")
    assertEquals(
      "$baseUrl/preset/profile/status?subscriber_id=s",
      assertNotNull(transport.lastRequest).url,
    )
  }

  // endregion
}
