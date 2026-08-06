package com.helium.passpoint

import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue
import org.junit.Test

/**
 * Asserts the Kotlin SDK agrees with `core/contract/contract.json`. The Swift
 * and TypeScript suites assert the same file, so a drift in any one SDK fails
 * that SDK's build with the exact missing symbol.
 */
class ContractConformanceTest {
  private val contract = Fixtures.contract()

  @Test
  fun `error codes match exactly`() {
    val expected = contract.getJSONArray("errorCodes")
      .let { array -> (0 until array.length()).map { array.getString(it) } }
      .toSet()
    val actual = PasspointErrorCode.values().map { it.name }.toSet()

    assertEquals(
      emptySet(),
      actual - expected,
      "codes in Kotlin that are missing from contract.json",
    )
    assertEquals(
      emptySet(),
      expected - actual,
      "codes in contract.json that are missing from Kotlin",
    )
  }

  @Test
  fun `environment base urls match`() {
    val environments = contract.getJSONObject("environments")
    for (name in environments.keys()) {
      assertEquals(
        environments.getString(name),
        PasspointEnvironment.named(name).baseUrl,
        "base URL for $name",
      )
    }
    assertEquals(3, environments.length(), "a new environment needs a PasspointEnvironment case")
  }

  @Test
  fun `default environment matches`() {
    val name = contract.getString("defaultEnvironment")
    assertEquals(
      PasspointEnvironment.named(name).baseUrl,
      PasspointConfig(apiKey = "k").environment.baseUrl,
    )
  }

  @Test
  fun `eap types match`() {
    val eapTypes = contract.getJSONObject("eapTypes")
    assertEquals(eapTypes.getInt("TLS"), EapType.TLS.value)
    assertEquals(eapTypes.getInt("TTLS"), EapType.TTLS.value)
    assertEquals(eapTypes.getInt("PEAP"), EapType.PEAP.value)
    assertEquals(eapTypes.length(), EapType.values().size)
  }

  @Test
  fun `default eap type matches`() {
    assertEquals(contract.getInt("defaultEapType"), PasspointConfig(apiKey = "k").eapType.value)
  }

  @Test
  fun `api paths and header match`() {
    val api = contract.getJSONObject("api")
    assertEquals(api.getString("apiKeyHeader"), ProfileApiClient.API_KEY_HEADER)
    assertEquals(api.getString("generateProfilePath"), ProfileApiClient.GENERATE_PROFILE_PATH)
    assertEquals(api.getString("profileStatusPath"), ProfileApiClient.PROFILE_STATUS_PATH)
    assertEquals(
      api.getString("statusSubscriberQueryParam"),
      ProfileApiClient.STATUS_SUBSCRIBER_QUERY_PARAM,
    )
  }

  @Test
  fun `csr common name template and signature algorithm match`() {
    val csr = contract.getJSONObject("csr")
    val expected = csr.getString("commonNameTemplate").replace("{subscriberId}", "abc-123")
    assertEquals(expected, CsrGenerator.commonName("abc-123"))
    assertEquals(csr.getString("signatureAlgorithm"), CsrGenerator.SIGNATURE_ALGORITHM)
  }

  /**
   * The key size the SDK actually generates, not the one the tests happen to
   * hand it — dropping to RSA-1024 must fail here.
   */
  @Test
  fun `csr key size matches`() {
    assertEquals(
      contract.getJSONObject("csr").getInt("keySizeBits"),
      KeyStoreManager.KEY_SIZE_BITS,
    )
  }

  /**
   * Without this the mapping loop below iterates whatever happens to be in the
   * file — deleting every status key would leave all three suites green.
   */
  @Test
  fun `http status mapping covers the expected statuses`() {
    val mapping = contract.getJSONObject("httpStatusMapping")
    val keys = mapping.keys().asSequence().filterNot { it == "\$comment" }.toSet()
    assertEquals(setOf("401", "403", "429", "default"), keys)
  }

  @Test
  fun `http status mapping matches`() {
    val mapping = contract.getJSONObject("httpStatusMapping")
    for (key in mapping.keys()) {
      if (key == "default" || key == "\$comment") continue
      val status = key.toInt()
      val error = assertFailsWith<PasspointException> {
        ProfileApiClient.throwIfErrorStatus(status, "")
      }
      assertEquals(mapping.getString(key), error.code.name, "mapping for HTTP $status")
    }

    val fallback = mapping.getString("default")
    for (status in listOf(400, 418, 500, 502)) {
      val error = assertFailsWith<PasspointException> {
        ProfileApiClient.throwIfErrorStatus(status, "")
      }
      assertEquals(fallback, error.code.name, "default mapping for HTTP $status")
    }
  }

  @Test
  fun `success statuses do not throw`() {
    for (status in listOf(200, 201, 204, 299)) {
      ProfileApiClient.throwIfErrorStatus(status, "")
    }
    assertTrue(true)
  }
}
