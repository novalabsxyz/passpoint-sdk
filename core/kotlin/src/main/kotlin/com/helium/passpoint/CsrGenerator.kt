package com.helium.passpoint

import java.security.KeyPair
import java.util.Base64
import javax.security.auth.x500.X500Principal
import org.bouncycastle.jce.provider.BouncyCastleProvider
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder
import org.bouncycastle.pkcs.jcajce.JcaPKCS10CertificationRequestBuilder

/**
 * Builds PKCS#10 Certificate Signing Requests with BouncyCastle.
 *
 * Contains no Android APIs (`java.util.Base64` rather than `android.util.Base64`),
 * so the unit tests generate a real CSR on the JVM and verify it.
 */
internal class CsrGenerator {
  companion object {
    const val SIGNATURE_ALGORITHM = "SHA256withRSA"

    /**
     * The literal `DOMAIN` is a sentinel the HIB inventory service substitutes
     * with the partner's first NAI realm when issuing the certificate.
     */
    fun commonName(subscriberId: String): String = "anonymous@$subscriberId.DOMAIN"
  }

  /**
   * Returns a PEM-encoded PKCS#10 CSR.
   *
   * @throws PasspointException with [PasspointErrorCode.CSR_GENERATION_FAILED].
   */
  fun generate(subscriberId: String, keyPair: KeyPair): String {
    ensureBouncyCastle()
    try {
      val subject = X500Principal("CN=${commonName(subscriberId)}")
      val builder = JcaPKCS10CertificationRequestBuilder(subject, keyPair.public)
      val signer = JcaContentSignerBuilder(SIGNATURE_ALGORITHM).build(keyPair.private)
      val der = builder.build(signer).encoded
      val pem = Base64.getEncoder().encodeToString(der)
      return "-----BEGIN CERTIFICATE REQUEST-----\n$pem\n-----END CERTIFICATE REQUEST-----"
    } catch (e: Exception) {
      throw PasspointException(
        PasspointErrorCode.CSR_GENERATION_FAILED,
        "Failed to generate CSR: ${e.message}",
        e,
      )
    }
  }

  private fun ensureBouncyCastle() {
    if (java.security.Security.getProvider(BouncyCastleProvider.PROVIDER_NAME) == null) {
      java.security.Security.addProvider(BouncyCastleProvider())
    }
  }
}
