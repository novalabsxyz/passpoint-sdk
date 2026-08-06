package com.helium.passpoint

import android.content.Context
import android.util.Log
import java.io.File
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec

/**
 * Manages the RSA keypair used for Passpoint credential provisioning.
 *
 * Android's `PasspointConfiguration.Credential.clientPrivateKey` requires an
 * *extractable* private key — the framework calls `.encoded` on it internally.
 * AndroidKeyStore keys are deliberately non-extractable, so the keypair is a
 * plain JCA keypair the SDK persists itself.
 *
 * It is stored in [Context.getNoBackupFilesDir], **not** SharedPreferences.
 * App-private prefs are included in Android's automatic backup by default, so a
 * key kept there would be uploaded to the user's Google account and restored
 * onto other devices. `no_backup` is excluded from both Auto Backup and
 * Device-to-Device transfer by the platform, with no manifest changes required
 * of the host app. Earlier SDK versions used SharedPreferences; [getKeyPair]
 * migrates and erases them on first use.
 *
 * The key only ever authenticates a TLS session with the RADIUS server, and it
 * is regenerated on every [PasspointClient.install].
 */
internal class KeyStoreManager(context: Context) {
  private val appContext = context.applicationContext

  private val keyDir: File
    get() = File(appContext.noBackupFilesDir, DIR_NAME)

  private val privateKeyFile: File
    get() = File(keyDir, PRIVATE_KEY_FILE)

  private val publicKeyFile: File
    get() = File(keyDir, PUBLIC_KEY_FILE)

  /** Legacy location; read once for migration, then cleared. */
  private val legacyPrefs
    get() = appContext.getSharedPreferences(LEGACY_PREFS_NAME, Context.MODE_PRIVATE)

  fun getOrCreateKeyPair(): KeyPair = getKeyPair() ?: createKeyPair()

  fun hasKeyPair(): Boolean =
    (privateKeyFile.exists() && publicKeyFile.exists()) ||
      legacyPrefs.contains(LEGACY_KEY_PRIVATE)

  fun deleteKeyPair() {
    privateKeyFile.delete()
    publicKeyFile.delete()
    clearLegacyPrefs()
    Log.d(TAG, "deleteKeyPair: deleted")
  }

  private fun getKeyPair(): KeyPair? {
    migrateLegacyKeyPairIfPresent()

    if (!privateKeyFile.exists() || !publicKeyFile.exists()) return null
    return try {
      decode(privateKeyFile.readBytes(), publicKeyFile.readBytes())
    } catch (e: Exception) {
      Log.w(TAG, "getKeyPair: stored keypair unreadable, regenerating", e)
      deleteKeyPair()
      null
    }
  }

  /**
   * Move a keypair written by an older SDK version out of SharedPreferences.
   * The prefs copy is erased whether or not it could be decoded — leaving it
   * behind is the whole problem being fixed.
   */
  private fun migrateLegacyKeyPairIfPresent() {
    val prefs = legacyPrefs
    val privateB64 = prefs.getString(LEGACY_KEY_PRIVATE, null) ?: return
    val publicB64 = prefs.getString(LEGACY_KEY_PUBLIC, null)

    try {
      if (publicB64 != null && !privateKeyFile.exists()) {
        val decoder = java.util.Base64.getDecoder()
        write(decoder.decode(privateB64), decoder.decode(publicB64))
        Log.d(TAG, "migrateLegacyKeyPair: moved keypair to no_backup storage")
      }
    } catch (e: Exception) {
      Log.w(TAG, "migrateLegacyKeyPair: could not migrate, discarding", e)
    } finally {
      clearLegacyPrefs()
    }
  }

  private fun clearLegacyPrefs() {
    legacyPrefs.edit().remove(LEGACY_KEY_PRIVATE).remove(LEGACY_KEY_PUBLIC).apply()
  }

  private fun createKeyPair(): KeyPair {
    Log.d(TAG, "createKeyPair: generating RSA-$KEY_SIZE_BITS")
    val generator = KeyPairGenerator.getInstance(KEY_ALGORITHM)
    generator.initialize(KEY_SIZE_BITS)
    val keyPair = generator.generateKeyPair()
    write(keyPair.private.encoded, keyPair.public.encoded)
    return keyPair
  }

  private fun write(privateDer: ByteArray, publicDer: ByteArray) {
    keyDir.mkdirs()
    privateKeyFile.writeBytes(privateDer)
    publicKeyFile.writeBytes(publicDer)
    // Owner-only, in case the app's data dir permissions are ever loosened.
    privateKeyFile.setReadable(false, false)
    privateKeyFile.setReadable(true, true)
  }

  private fun decode(privateDer: ByteArray, publicDer: ByteArray): KeyPair {
    val factory = KeyFactory.getInstance(KEY_ALGORITHM)
    return KeyPair(
      factory.generatePublic(X509EncodedKeySpec(publicDer)),
      factory.generatePrivate(PKCS8EncodedKeySpec(privateDer)),
    )
  }

  internal companion object {
    /** Asserted against `contract.json` by ContractConformanceTest. */
    const val KEY_SIZE_BITS = 2048

    private const val TAG = "KeyStoreManager"
    private const val DIR_NAME = "helium-passpoint"
    private const val PRIVATE_KEY_FILE = "client-key.pk8"
    private const val PUBLIC_KEY_FILE = "client-key.spki"
    private const val KEY_ALGORITHM = "RSA"

    private const val LEGACY_PREFS_NAME = "helium_passpoint_keys"
    private const val LEGACY_KEY_PRIVATE = "private_key"
    private const val LEGACY_KEY_PUBLIC = "public_key"
  }
}
