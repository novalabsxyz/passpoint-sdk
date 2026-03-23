package com.helium.passpoint

import android.util.Base64
import java.io.ByteArrayInputStream
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

class CertificateStore {
  private val certFactory: CertificateFactory = CertificateFactory.getInstance("X.509")

  fun parsePEM(pem: String): X509Certificate {
    val cleaned = pem
      .replace("-----BEGIN CERTIFICATE-----", "")
      .replace("-----END CERTIFICATE-----", "")
      .replace("\n", "")
      .trim()
    val data = Base64.decode(cleaned, Base64.DEFAULT)
    return certFactory.generateCertificate(ByteArrayInputStream(data)) as X509Certificate
  }

  fun expirationISO(cert: X509Certificate): String? {
    val notAfter = cert.notAfter ?: return null
    val formatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
    formatter.timeZone = TimeZone.getTimeZone("UTC")
    return formatter.format(notAfter)
  }

  fun subjectCN(cert: X509Certificate): String? {
    val dn = cert.subjectX500Principal?.name ?: return null
    // Extract CN= value
    return dn.split(",")
      .map { it.trim() }
      .firstOrNull { it.startsWith("CN=") }
      ?.removePrefix("CN=")
  }
}
