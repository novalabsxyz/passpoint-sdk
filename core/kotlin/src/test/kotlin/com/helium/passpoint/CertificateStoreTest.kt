package com.helium.passpoint

import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import org.junit.Test

class CertificateStoreTest {
  private val store = CertificateStore()

  // region PEM

  @Test
  fun `parses a pem certificate`() {
    val cert = store.parsePem(Fixtures.text("testLeaf.crt"))
    assertEquals("anonymous@subscriber-42.helium.example", store.subjectCn(cert))
  }

  @Test
  fun `parses pem with crlf line endings`() {
    val crlf = Fixtures.text("testLeaf.crt").replace("\n", "\r\n")
    assertNotNull(store.parsePem(crlf))
  }

  @Test
  fun `parses pem without a trailing newline`() {
    assertNotNull(store.parsePem(Fixtures.text("testLeaf.crt").trim()))
  }

  @Test
  fun `rejects garbage`() {
    assertThrowsPasspoint(PasspointErrorCode.CERTIFICATE_PARSE_FAILED) { store.parsePem("") }
    assertThrowsPasspoint(PasspointErrorCode.CERTIFICATE_PARSE_FAILED) {
      store.parsePem("-----BEGIN CERTIFICATE-----\n!!!not base64!!!\n-----END CERTIFICATE-----")
    }
  }

  // endregion

  // region Expiry — the same fixtures the Swift suite asserts against

  @Test
  fun `reads a utctime expiry`() {
    val cert = store.parsePem(Fixtures.text("testLeaf.crt"))
    assertEquals(Instant.parse("2035-01-01T00:00:00Z"), store.expiration(cert))
  }

  @Test
  fun `reads a generalizedtime expiry`() {
    val cert = store.parsePem(Fixtures.text("testLeafGeneralized.crt"))
    assertEquals(Instant.parse("2060-01-01T00:00:00Z"), store.expiration(cert))
  }

  // endregion

  // region Realm derivation

  /**
   * The realm must come from the certificate CN, not the HomeSP FQDN — see
   * [CertificateStore.realmFromCert]. Getting this wrong makes every EAP-TLS
   * session fail at the AAA server with an identity mismatch.
   */
  @Test
  fun `derives the realm from the certificate common name`() {
    val cert = store.parsePem(Fixtures.text("testLeaf.crt"))
    assertEquals(
      "subscriber-42.helium.example",
      store.realmFromCert(cert, fallback = "wrong.example"),
    )
  }

  @Test
  fun `derives the realm for a second subscriber`() {
    val cert = store.parsePem(Fixtures.text("testLeafGeneralized.crt"))
    assertEquals("subscriber-99.helium.example", store.realmFromCert(cert, "fallback.example"))
  }

  /** Without an `@` in the CN there is no realm to take, so the HomeSP FQDN wins. */
  @Test
  fun `falls back when the common name has no at sign`() {
    val cert = store.parsePem(Fixtures.text("testLeafNoRealm.crt"))
    assertEquals("fallback.example", store.realmFromCert(cert, "fallback.example"))
  }

  @Test
  fun `reads the common name of a certificate without a realm`() {
    val cert = store.parsePem(Fixtures.text("testLeafNoRealm.crt"))
    assertEquals("plain-common-name", store.subjectCn(cert))
  }

  // endregion
}
