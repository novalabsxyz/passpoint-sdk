package com.helium.passpoint

import java.io.ByteArrayInputStream
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.time.Instant
import java.util.Base64

/**
 * X.509 helpers. Contains no Android APIs (`java.util.Base64` rather than
 * `android.util.Base64`), so it is unit-tested directly on the JVM.
 */
internal class CertificateStore {
  private val certFactory: CertificateFactory = CertificateFactory.getInstance("X.509")

  /**
   * Parse a PEM certificate. Tolerates CRLF, missing trailing newline and
   * arbitrary whitespace inside the base64 body.
   *
   * @throws PasspointException with [PasspointErrorCode.CERTIFICATE_PARSE_FAILED].
   */
  fun parsePem(pem: String): X509Certificate {
    try {
      val body = pem
        .replace("-----BEGIN CERTIFICATE-----", "")
        .replace("-----END CERTIFICATE-----", "")
      val der = Base64.getMimeDecoder().decode(body)
      return certFactory.generateCertificate(ByteArrayInputStream(der)) as X509Certificate
    } catch (e: Exception) {
      throw PasspointException(
        PasspointErrorCode.CERTIFICATE_PARSE_FAILED,
        "Failed to parse certificate: ${e.message}",
        e,
      )
    }
  }

  fun expiration(cert: X509Certificate): Instant? = cert.notAfter?.toInstant()

  fun subjectCn(cert: X509Certificate): String? = commonName(cert)

  /**
   * The EAP-TLS outer identity Android emits is `anonymous@<Credential.realm>`.
   * For the AAA server to match it to the client certificate the realm must be
   * the realm portion of the certificate's subject CN
   * (`anonymous@<subscriberId>.<realm>`) — i.e. everything after the `@` — and
   * *not* the HomeSP FQDN. iOS derives the outer identity from the certificate
   * automatically; this mirrors that.
   *
   * @param fallback returned when the CN is absent or contains no `@`.
   */
  fun realmFromCert(cert: X509Certificate, fallback: String): String =
    try {
      val cn = commonName(cert)
      cn?.substringAfter('@', "")?.ifBlank { null } ?: fallback
    } catch (_: Exception) {
      // X500Principal.getName() throws on DNs with unsupported AVA encodings.
      // A wrong realm breaks authentication; an exception here would break the
      // whole install, so fall back to the HomeSP FQDN.
      fallback
    }

  private fun commonName(cert: X509Certificate): String? {
    val dn = cert.subjectX500Principal?.name ?: return null
    return CN_PATTERN.find(dn)?.groupValues?.get(1)?.trim()
  }

  private companion object {
    /** Matches `CN=value` at the start of the DN or after a comma. */
    val CN_PATTERN = Regex("(?:^|,)\\s*CN=([^,]+)")
  }
}
