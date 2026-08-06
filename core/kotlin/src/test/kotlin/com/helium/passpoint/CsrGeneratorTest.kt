package com.helium.passpoint

import java.util.Base64
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.bouncycastle.operator.jcajce.JcaContentVerifierProviderBuilder
import org.bouncycastle.pkcs.PKCS10CertificationRequest
import org.junit.Test

class CsrGeneratorTest {
  private val keyPair = TestKeys.rsaKeyPair()
  private val generator = CsrGenerator()

  private fun der(pem: String): ByteArray =
    Base64.getMimeDecoder().decode(
      pem
        .replace("-----BEGIN CERTIFICATE REQUEST-----", "")
        .replace("-----END CERTIFICATE REQUEST-----", "")
    )

  @Test
  fun `produces pem armoured output`() {
    val pem = generator.generate("subscriber-42", keyPair)
    assertTrue(pem.startsWith("-----BEGIN CERTIFICATE REQUEST-----\n"))
    assertTrue(pem.endsWith("\n-----END CERTIFICATE REQUEST-----"))
  }

  @Test
  fun `common name carries the domain sentinel`() {
    assertEquals("anonymous@subscriber-42.DOMAIN", CsrGenerator.commonName("subscriber-42"))
  }

  @Test
  fun `encodes the expected subject`() {
    val request = PKCS10CertificationRequest(der(generator.generate("sub-abc", keyPair)))
    assertEquals("CN=anonymous@sub-abc.DOMAIN", request.subject.toString())
  }

  /**
   * Re-verify the PKCS#10 signature. This only passes if the whole structure is
   * well formed, because the signature covers the encoded CertificationRequestInfo.
   */
  @Test
  fun `signature verifies`() {
    val request = PKCS10CertificationRequest(der(generator.generate("subscriber-42", keyPair)))
    val verifier = JcaContentVerifierProviderBuilder().build(keyPair.public)
    assertTrue(request.isSignatureValid(verifier), "CSR signature did not verify")
  }

  @Test
  fun `embeds the signing public key`() {
    val request = PKCS10CertificationRequest(der(generator.generate("subscriber-42", keyPair)))
    assertTrue(
      request.subjectPublicKeyInfo.encoded.contentEquals(keyPair.public.encoded),
      "the CSR should carry the SubjectPublicKeyInfo of the signing key",
    )
  }

  /**
   * Kotlin emits one unbroken base64 line; the Swift SDK wraps at 64 characters
   * (`.lineLength64Characters`). Both are valid PEM and the inventory API
   * accepts either, but the shapes are NOT identical — see the matching Swift
   * test. Pinned here so neither side changes by accident.
   */
  @Test
  fun `body has no internal newlines`() {
    val pem = generator.generate("subscriber-42", keyPair)
    val body = pem.lines().drop(1).dropLast(1)
    assertEquals(1, body.size, "expected a single base64 line, got ${body.size}")
  }

  @Test
  fun `subscriber ids with punctuation survive round trip`() {
    for (id in listOf("sub_1", "sub.2", "sub-3", "0123456789")) {
      val request = PKCS10CertificationRequest(der(generator.generate(id, keyPair)))
      assertEquals("CN=anonymous@$id.DOMAIN", request.subject.toString())
    }
  }

  @Test
  fun `wraps failures as CSR_GENERATION_FAILED`() {
    // A public-key-only "pair": signing has nothing to sign with.
    val broken = java.security.KeyPair(keyPair.public, null)
    assertThrowsPasspoint(PasspointErrorCode.CSR_GENERATION_FAILED) {
      generator.generate("subscriber-42", broken)
    }
  }
}
