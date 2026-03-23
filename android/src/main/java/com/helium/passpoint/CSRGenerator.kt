package com.helium.passpoint

import android.util.Base64
import java.security.KeyPair
import java.security.PrivateKey
import java.security.Signature
import javax.security.auth.x500.X500Principal
import org.bouncycastle.asn1.x509.AlgorithmIdentifier
import org.bouncycastle.asn1.pkcs.PKCSObjectIdentifiers
import org.bouncycastle.asn1.x509.SubjectPublicKeyInfo
import org.bouncycastle.operator.ContentSigner
import org.bouncycastle.pkcs.PKCS10CertificationRequestBuilder
import java.io.ByteArrayOutputStream
import java.io.OutputStream

class CSRGenerator {

  fun generate(userIdentifier: String, domain: String, keyPair: KeyPair): String {
    val subject = org.bouncycastle.asn1.x500.X500Name("CN=anonymous@${userIdentifier}.${domain}")
    val pubKeyInfo = SubjectPublicKeyInfo.getInstance(keyPair.public.encoded)
    val builder = PKCS10CertificationRequestBuilder(subject, pubKeyInfo)

    // Use a custom ContentSigner that delegates to the Android KeyStore provider.
    // AndroidKeyStore private keys are non-extractable, so BouncyCastle's default
    // JcaContentSignerBuilder (which uses its own provider) cannot access them.
    val signer = AndroidKeyStoreSigner(keyPair.private)
    val csr = builder.build(signer)
    val pem = Base64.encodeToString(csr.encoded, Base64.NO_WRAP)
    return "-----BEGIN CERTIFICATE REQUEST-----\n$pem\n-----END CERTIFICATE REQUEST-----"
  }
}

/**
 * ContentSigner that uses java.security.Signature directly, allowing
 * AndroidKeyStore private keys to sign without extracting key material.
 */
private class AndroidKeyStoreSigner(private val privateKey: PrivateKey) : ContentSigner {
  private val outputStream = ByteArrayOutputStream()

  override fun getAlgorithmIdentifier(): AlgorithmIdentifier {
    return AlgorithmIdentifier(PKCSObjectIdentifiers.sha256WithRSAEncryption)
  }

  override fun getOutputStream(): OutputStream = outputStream

  override fun getSignature(): ByteArray {
    val sig = Signature.getInstance("SHA256withRSA")
    sig.initSign(privateKey)
    sig.update(outputStream.toByteArray())
    return sig.sign()
  }
}
