package com.helium.passpoint

import android.content.Context
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSuggestion
import android.net.wifi.hotspot2.PasspointConfiguration
import android.net.wifi.hotspot2.pps.Credential
import android.net.wifi.hotspot2.pps.HomeSp
import android.os.Build
import android.util.Log
import java.security.KeyPair
import java.security.MessageDigest
import java.security.cert.X509Certificate

class HotspotConfigurator(private val context: Context) {
  private val tag = "HotspotConfigurator"
  private val prefs = context.getSharedPreferences("helium_passpoint", Context.MODE_PRIVATE)
  private val PREF_INSTALLED = "profile_installed"

  data class ProfileConfig(
    val domainName: String,
    val friendlyName: String,
    val clientCert: X509Certificate,
    val caCerts: List<X509Certificate>,
    val serverCaCert: X509Certificate,
    val keyPair: KeyPair,
  )

  fun install(config: ProfileConfig) {
    val passpointConfig = buildPasspointConfig(config)
    applyPasspoint(passpointConfig)
    prefs.edit().putBoolean(PREF_INSTALLED, true).apply()
  }

  fun removeAll() {
    val wifi = wifiManager()

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
      val suggestions = wifi.networkSuggestions
      if (suggestions.isNotEmpty()) {
        wifi.removeNetworkSuggestions(suggestions)
        Log.d(tag, "removeAll: removed ${suggestions.size} suggestions")
      }
    }

    try {
      @Suppress("DEPRECATION")
      val configs = wifi.passpointConfigurations ?: emptyList()
      for (c in configs) {
        c.homeSp?.fqdn?.let {
          wifi.removePasspointConfiguration(it)
          Log.d(tag, "removeAll: removed passpoint config $it")
        }
      }
    } catch (e: Exception) {
      Log.w(tag, "removeAll: passpoint config removal failed", e)
    }

    prefs.edit().putBoolean(PREF_INSTALLED, false).apply()
  }

  fun isInstalled(): Boolean {
    return prefs.getBoolean(PREF_INSTALLED, false)
  }

  private fun buildPasspointConfig(config: ProfileConfig): PasspointConfiguration {
    val homeSp = HomeSp().apply {
      fqdn = config.domainName
      friendlyName = config.friendlyName
    }

    val clientChain = (listOf(config.clientCert) + config.caCerts).toTypedArray()
    val fingerprint = MessageDigest.getInstance("SHA-256").digest(config.clientCert.encoded)

    val credential = Credential().apply {
      realm = config.domainName
      try {
        val method = this.javaClass.getMethod(
          "setCheckAaaServerCertStatus", Boolean::class.javaPrimitiveType
        )
        method.invoke(this, true)
      } catch (_: Exception) {}
      certCredential = Credential.CertificateCredential().apply {
        certType = "x509v3"
        certSha256Fingerprint = fingerprint
      }
      clientCertificateChain = clientChain
      clientPrivateKey = config.keyPair.private
      caCertificate = config.serverCaCert
    }

    val passpointConfig = PasspointConfiguration().apply {
      this.homeSp = homeSp
      this.credential = credential
    }

    if (Build.VERSION.SDK_INT >= 31) {
      try {
        val field = passpointConfig.javaClass.getDeclaredField("aaaServerTrustedNames")
        field.isAccessible = true
        field.set(passpointConfig, arrayOf(config.domainName))
      } catch (_: Exception) {}
    }

    return passpointConfig
  }

  private fun applyPasspoint(config: PasspointConfiguration) {
    val wifi = wifiManager()

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
      val suggestion = WifiNetworkSuggestion.Builder()
        .setPasspointConfig(config)
        .build()

      val existing = wifi.networkSuggestions
      if (existing.isNotEmpty()) {
        wifi.removeNetworkSuggestions(existing)
      }

      val result = wifi.addNetworkSuggestions(listOf(suggestion))
      when (result) {
        WifiManager.STATUS_NETWORK_SUGGESTIONS_SUCCESS -> {}
        WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_ADD_DUPLICATE -> {}
        WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_APP_DISALLOWED ->
          throw PasspointSDKException("NETWORK_SUGGESTION_DISALLOWED",
            "App is not allowed to add network suggestions. User may have disabled this.")
        WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_INTERNAL ->
          throw PasspointSDKException("PROFILE_INSTALL_FAILED",
            "Internal error adding network suggestion")
        WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_ADD_EXCEEDS_MAX_PER_APP ->
          throw PasspointSDKException("NETWORK_SUGGESTION_LIMIT",
            "Exceeded maximum network suggestions per app")
        else ->
          throw PasspointSDKException("PROFILE_INSTALL_FAILED",
            "Failed to add network suggestion: error code $result")
      }
    } else {
      try {
        wifi.addOrUpdatePasspointConfiguration(config)
      } catch (e: Exception) {
        throw PasspointSDKException("PROFILE_INSTALL_FAILED",
          "Failed to apply Passpoint config: ${e.message}", e)
      }
    }
  }

  private fun wifiManager(): WifiManager {
    return context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
      ?: throw PasspointSDKException("WIFI_MANAGER_UNAVAILABLE", "WifiManager not available")
  }
}

/**
 * Exception with a typed error code that maps to PasspointErrorCode on the TS side.
 */
class PasspointSDKException(
  val errorCode: String,
  override val message: String,
  cause: Throwable? = null,
) : Exception(message, cause)
