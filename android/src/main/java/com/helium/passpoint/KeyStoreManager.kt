package com.helium.passpoint

import android.content.Context
import android.content.SharedPreferences
import android.util.Base64
import android.util.Log
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec

/**
 * Manages RSA keypairs for Passpoint credential provisioning.
 *
 * Note: Android's PasspointConfiguration.Credential.clientPrivateKey requires
 * an extractable private key (it calls .encoded internally). AndroidKeyStore
 * keys are non-extractable, so we use a standard Java keypair stored in
 * SharedPreferences. The keys are only used for TLS client authentication
 * with the RADIUS server, not for long-term storage of secrets.
 */
class KeyStoreManager(context: Context) {
  private val tag = "KeyStoreManager"
  private val prefs: SharedPreferences =
    context.getSharedPreferences("helium_passpoint_keys", Context.MODE_PRIVATE)

  fun getOrCreateKeyPair(): KeyPair {
    getKeyPair()?.let { return it }
    return createKeyPair()
  }

  fun deleteKeyPair() {
    prefs.edit()
      .remove("private_key")
      .remove("public_key")
      .apply()
    Log.d(tag, "deleteKeyPair: deleted")
  }

  private fun getKeyPair(): KeyPair? {
    val privateB64 = prefs.getString("private_key", null) ?: return null
    val publicB64 = prefs.getString("public_key", null) ?: return null

    return try {
      val keyFactory = KeyFactory.getInstance("RSA")
      val privateKey = keyFactory.generatePrivate(
        PKCS8EncodedKeySpec(Base64.decode(privateB64, Base64.NO_WRAP))
      )
      val publicKey = keyFactory.generatePublic(
        X509EncodedKeySpec(Base64.decode(publicB64, Base64.NO_WRAP))
      )
      KeyPair(publicKey, privateKey)
    } catch (e: Exception) {
      Log.w(tag, "getKeyPair: failed to restore, will regenerate", e)
      deleteKeyPair()
      null
    }
  }

  private fun createKeyPair(): KeyPair {
    Log.d(tag, "createKeyPair: generating RSA-2048")
    val generator = KeyPairGenerator.getInstance("RSA")
    generator.initialize(2048)
    val keyPair = generator.generateKeyPair()

    prefs.edit()
      .putString("private_key", Base64.encodeToString(keyPair.private.encoded, Base64.NO_WRAP))
      .putString("public_key", Base64.encodeToString(keyPair.public.encoded, Base64.NO_WRAP))
      .apply()

    return keyPair
  }
}
