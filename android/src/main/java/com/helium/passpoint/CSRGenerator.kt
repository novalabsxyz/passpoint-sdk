package com.helium.passpoint

import android.util.Base64
import java.security.KeyPair
import javax.security.auth.x500.X500Principal
import org.bouncycastle.jce.provider.BouncyCastleProvider
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder
import org.bouncycastle.pkcs.jcajce.JcaPKCS10CertificationRequestBuilder

class CSRGenerator {

  fun generate(subscriberId: String, keyPair: KeyPair): String {
    ensureBouncyCastle()

    // The literal "DOMAIN" is a sentinel the HIB inventory service substitutes
    // with the partner's first NAI realm when issuing the certificate.
    val subject = X500Principal("CN=anonymous@${subscriberId}.DOMAIN")
    val builder = JcaPKCS10CertificationRequestBuilder(subject, keyPair.public)
    val signer = JcaContentSignerBuilder("SHA256withRSA").build(keyPair.private)
    val csr = builder.build(signer)
    val pem = Base64.encodeToString(csr.encoded, Base64.NO_WRAP)
    return "-----BEGIN CERTIFICATE REQUEST-----\n$pem\n-----END CERTIFICATE REQUEST-----"
  }

  private fun ensureBouncyCastle() {
    if (java.security.Security.getProvider(BouncyCastleProvider.PROVIDER_NAME) == null) {
      java.security.Security.addProvider(BouncyCastleProvider())
    }
  }
}
