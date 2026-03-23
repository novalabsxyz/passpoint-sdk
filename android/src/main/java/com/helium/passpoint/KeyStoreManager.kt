package com.helium.passpoint

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Log
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.KeyStore

/**
 * Manages RSA keypairs in Android KeyStore (hardware-backed when available).
 * Private key material never leaves the secure enclave.
 */
class KeyStoreManager(
  private val keyAlias: String = "com.helium.passpoint.rsa-key",
) {
  private val tag = "KeyStoreManager"

  fun getOrCreateKeyPair(): KeyPair {
    getKeyPair()?.let { return it }
    return createKeyPair()
  }

  fun deleteKeyPair() {
    try {
      val keyStore = loadKeyStore()
      if (keyStore.containsAlias(keyAlias)) {
        keyStore.deleteEntry(keyAlias)
        Log.d(tag, "deleteKeyPair: deleted")
      }
    } catch (e: Exception) {
      Log.w(tag, "deleteKeyPair: failed", e)
    }
  }

  private fun getKeyPair(): KeyPair? {
    return try {
      val keyStore = loadKeyStore()
      if (!keyStore.containsAlias(keyAlias)) return null

      val entry = keyStore.getEntry(keyAlias, null) as? KeyStore.PrivateKeyEntry ?: return null
      KeyPair(entry.certificate.publicKey, entry.privateKey)
    } catch (e: Exception) {
      Log.w(tag, "getKeyPair: failed", e)
      null
    }
  }

  private fun createKeyPair(): KeyPair {
    Log.d(tag, "createKeyPair: generating RSA-2048 in AndroidKeyStore")
    val generator = KeyPairGenerator.getInstance(
      KeyProperties.KEY_ALGORITHM_RSA, "AndroidKeyStore"
    )
    generator.initialize(
      KeyGenParameterSpec.Builder(
        keyAlias,
        KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY
      )
        .setKeySize(2048)
        .setDigests(KeyProperties.DIGEST_SHA256)
        .setSignaturePaddings(KeyProperties.SIGNATURE_PADDING_RSA_PKCS1)
        .build()
    )
    return generator.generateKeyPair()
  }

  private fun loadKeyStore(): KeyStore {
    return KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
  }
}
