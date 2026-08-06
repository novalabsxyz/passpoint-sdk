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

/**
 * Wraps `WifiManager`, the Android API that installs and removes Hotspot 2.0
 * (Passpoint) profiles.
 *
 * On API 30+ profiles are installed as network *suggestions*; below that the
 * deprecated `addOrUpdatePasspointConfiguration` is used.
 */
internal class HotspotConfigurator(context: Context) {
  private val appContext = context.applicationContext
  private val prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
  private val certStore = CertificateStore()

  data class ProfileConfig(
    val domainName: String,
    val friendlyName: String,
    val naiRealmNames: List<String>,
    val trustedServerNames: List<String>,
    val clientCert: X509Certificate,
    val caCerts: List<X509Certificate>,
    val serverCaCert: X509Certificate,
    val keyPair: KeyPair,
  )

  fun install(config: ProfileConfig) {
    applyPasspoint(buildPasspointConfig(config))
    prefs.edit()
      .putBoolean(PREF_INSTALLED, true)
      .putString(PREF_FQDN, config.domainName)
      .apply()
  }

  /**
   * Remove only what this SDK installed.
   *
   * Network suggestions are app-wide, so a blanket
   * `removeNetworkSuggestions(wifi.networkSuggestions)` would also delete
   * suggestions the host app registered for its own networks. Suggestions are
   * matched by the Passpoint FQDN recorded at install time; when that is
   * unknown (an upgrade from a build that did not record it) the fallback is
   * still narrowed to suggestions that carry *any* Passpoint config, leaving
   * the host app's ordinary Wi-Fi suggestions alone.
   */
  @Suppress("DEPRECATION")
  fun removeAll() {
    val wifi = wifiManager()
    val ourFqdn = prefs.getString(PREF_FQDN, null)

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
      val ours = wifi.networkSuggestions.filter { suggestion ->
        val fqdn = suggestion.passpointConfig?.homeSp?.fqdn ?: return@filter false
        ourFqdn == null || fqdn == ourFqdn
      }
      if (ours.isNotEmpty()) {
        wifi.removeNetworkSuggestions(ours)
        Log.d(TAG, "removeAll: removed ${ours.size} of ${wifi.networkSuggestions.size} suggestions")
      }
    }

    try {
      // getPasspointConfigurations() is already scoped to the calling app, but
      // narrow to our own FQDN when we know it.
      val configs = (wifi.passpointConfigurations ?: emptyList())
        .mapNotNull { it.homeSp?.fqdn }
        .filter { ourFqdn == null || it == ourFqdn }
      for (fqdn in configs) {
        wifi.removePasspointConfiguration(fqdn)
        Log.d(TAG, "removeAll: removed passpoint config $fqdn")
      }
    } catch (e: Exception) {
      Log.w(TAG, "removeAll: passpoint config removal failed", e)
    }

    prefs.edit().putBoolean(PREF_INSTALLED, false).remove(PREF_FQDN).apply()
  }

  fun isInstalled(): Boolean = prefs.getBoolean(PREF_INSTALLED, false)

  /**
   * Whether the last install managed to apply AAA server-name validation and
   * certificate-status checking. Both are `@hide` on the platform and are set
   * reflectively, so they silently no-op behind the hidden-API blocklist on
   * API 28+. Surfaced through `PasspointClient.diagnostics()` so a support
   * ticket can tell the difference.
   */
  fun serverValidationApplied(): Pair<Boolean, Boolean> =
    prefs.getBoolean(PREF_AAA_STATUS_CHECK, false) to prefs.getBoolean(PREF_AAA_TRUSTED_NAMES, false)

  private fun buildPasspointConfig(config: ProfileConfig): PasspointConfiguration {
    val homeSp = HomeSp().apply {
      fqdn = config.domainName
      friendlyName = config.friendlyName
    }

    val clientChain = (listOf(config.clientCert) + config.caCerts).toTypedArray()
    val fingerprint = MessageDigest.getInstance("SHA-256").digest(config.clientCert.encoded)

    val credential = Credential().apply {
      // Android emits the EAP-TLS outer identity as anonymous@<Credential.realm>,
      // which the AAA server matches against the client certificate's subject CN.
      // See CertificateStore.realmFromCert.
      realm = certStore.realmFromCert(config.clientCert, config.domainName)
      enableAaaServerCertStatusCheck(this)
      certCredential = Credential.CertificateCredential().apply {
        certType = "x509v3"
        certSha256Fingerprint = fingerprint
      }
      clientCertificateChain = clientChain
      clientPrivateKey = config.keyPair.private
      caCertificate = config.serverCaCert
    }

    return PasspointConfiguration().apply {
      this.homeSp = homeSp
      this.credential = credential
      setAaaServerTrustedNames(this, config)
    }
  }

  /**
   * `setCheckAaaServerCertStatus` is `@hide`, so this is reflective and fails
   * silently behind the hidden-API blocklist on API 28+. The result is recorded
   * for diagnostics rather than swallowed without trace.
   *
   * Note this is *additional* hardening: the AAA server's certificate chain is
   * still validated against the Helium root CA through the public
   * `Credential.setCaCertificate`, which [buildPasspointConfig] always sets.
   * What can be lost here is OCSP status checking.
   */
  private fun enableAaaServerCertStatusCheck(credential: Credential) {
    val applied = try {
      credential.javaClass
        .getMethod("setCheckAaaServerCertStatus", Boolean::class.javaPrimitiveType)
        .invoke(credential, true)
      true
    } catch (e: Exception) {
      Log.w(TAG, "setCheckAaaServerCertStatus unavailable: ${e.javaClass.simpleName}")
      false
    }
    prefs.edit().putBoolean(PREF_AAA_STATUS_CHECK, applied).apply()
  }

  /**
   * `aaaServerTrustedNames` has no public setter, so this is reflective and can
   * silently no-op. When it does, Android validates the AAA server's chain
   * against the Helium root CA but does **not** pin the server *name* the way
   * iOS's `trustedServerNames` does. Recorded for diagnostics.
   */
  private fun setAaaServerTrustedNames(
    passpointConfig: PasspointConfiguration,
    config: ProfileConfig,
  ) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
      prefs.edit().putBoolean(PREF_AAA_TRUSTED_NAMES, false).apply()
      return
    }
    val applied = try {
      val field = passpointConfig.javaClass.getDeclaredField("aaaServerTrustedNames")
      field.isAccessible = true
      val trusted = config.trustedServerNames.ifEmpty { listOf(config.domainName) }
      field.set(passpointConfig, trusted.toTypedArray())
      true
    } catch (e: Exception) {
      Log.w(TAG, "aaaServerTrustedNames unavailable: ${e.javaClass.simpleName}")
      false
    }
    prefs.edit().putBoolean(PREF_AAA_TRUSTED_NAMES, applied).apply()
  }

  private fun applyPasspoint(config: PasspointConfiguration) {
    val wifi = wifiManager()

    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
      try {
        @Suppress("DEPRECATION")
        wifi.addOrUpdatePasspointConfiguration(config)
      } catch (e: Exception) {
        throw PasspointException(
          PasspointErrorCode.PROFILE_INSTALL_FAILED,
          "Failed to apply Passpoint config: ${e.message}",
          e,
        )
      }
      return
    }

    val suggestion = WifiNetworkSuggestion.Builder().setPasspointConfig(config).build()

    val existing = wifi.networkSuggestions
    if (existing.isNotEmpty()) wifi.removeNetworkSuggestions(existing)

    when (val result = wifi.addNetworkSuggestions(listOf(suggestion))) {
      WifiManager.STATUS_NETWORK_SUGGESTIONS_SUCCESS,
      WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_ADD_DUPLICATE -> Unit

      WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_APP_DISALLOWED ->
        throw PasspointException(
          PasspointErrorCode.NETWORK_SUGGESTION_DISALLOWED,
          "App is not allowed to add network suggestions. The user may have disabled this.",
        )

      WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_ADD_EXCEEDS_MAX_PER_APP ->
        throw PasspointException(
          PasspointErrorCode.NETWORK_SUGGESTION_LIMIT,
          "Exceeded the maximum number of network suggestions for this app.",
        )

      else ->
        throw PasspointException(
          PasspointErrorCode.PROFILE_INSTALL_FAILED,
          "Failed to add network suggestion: error code $result",
        )
    }
  }

  private fun wifiManager(): WifiManager =
    appContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
      ?: throw PasspointException(
        PasspointErrorCode.WIFI_MANAGER_UNAVAILABLE,
        "WifiManager is not available on this device.",
      )

  private companion object {
    const val TAG = "HotspotConfigurator"
    const val PREFS_NAME = "helium_passpoint"
    const val PREF_INSTALLED = "profile_installed"
    const val PREF_FQDN = "profile_fqdn"
    const val PREF_AAA_STATUS_CHECK = "aaa_status_check_applied"
    const val PREF_AAA_TRUSTED_NAMES = "aaa_trusted_names_applied"
  }
}
