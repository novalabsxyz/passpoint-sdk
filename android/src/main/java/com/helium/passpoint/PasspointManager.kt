package com.helium.passpoint

import android.content.Context
import android.util.Log
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.security.KeyPair
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import org.json.JSONArray
import org.json.JSONObject

class PasspointManager(private val context: Context) {
  private val tag = "PasspointManager"

  private var apiKey: String? = null
  private var baseUrl: String? = null
  private var eapType: Int = 13
  private var serverCaCertPem: String? = null
  private var presetId: String? = null

  private val keyStore = KeyStoreManager(context)
  private val csrGenerator = CSRGenerator()
  private val certStore = CertificateStore()
  private val hotspot by lazy { HotspotConfigurator(context) }

  // Persisted profile metadata so getCertificateInfo() reports the
  // domain/friendly name actually used for the installed Passpoint profile,
  // not the inventory API host.
  private val prefs = context.getSharedPreferences("helium_passpoint_manager", Context.MODE_PRIVATE)
  private val PREF_DOMAIN = "profile_domain"
  private val PREF_FRIENDLY_NAME = "profile_friendly_name"

  data class Profile(
    val friendlyName: String,
    val domainName: String,
    val naiRealmNames: List<String>,
    val trustedServerNames: List<String>,
    val tlsVersion: String,
    val certificate: String,
    val caChain: List<String>,
  )

  // MARK: - Configuration

  fun configure(apiKey: String, baseUrl: String, eapType: Int, serverCaCertPem: String?, presetId: String?) {
    this.apiKey = apiKey
    this.baseUrl = baseUrl.trimEnd('/')
    this.eapType = eapType
    this.serverCaCertPem = serverCaCertPem
    this.presetId = presetId
    Log.d(tag, "configured: baseUrl=$baseUrl, eapType=$eapType")
  }

  // MARK: - Install

  fun install(subscriberId: String): JSONObject {
    val apiKey = this.apiKey ?: throw PasspointSDKException("NOT_CONFIGURED", "SDK not configured")
    val baseUrl = this.baseUrl ?: throw PasspointSDKException("NOT_CONFIGURED", "SDK not configured")

    // 0. Remove any existing profile so only one cert is installed at a time
    hotspot.removeAll()
    keyStore.deleteKeyPair()

    // 1. Get or create keypair
    val keyPair: KeyPair
    try {
      keyPair = keyStore.getOrCreateKeyPair()
    } catch (e: Exception) {
      throw PasspointSDKException("KEYPAIR_GENERATION_FAILED", "Failed to get/create keypair: ${e.message}", e)
    }

    // 2. Generate CSR
    val csr: String
    try {
      csr = csrGenerator.generate(subscriberId, keyPair)
    } catch (e: Exception) {
      throw PasspointSDKException("CSR_GENERATION_FAILED", "Failed to generate CSR: ${e.message}", e)
    }

    // 3. Call API
    val profile = fetchProfile(csr, subscriberId, apiKey, baseUrl)

    // 4. Parse certs
    val clientCert: X509Certificate
    val caCerts: List<X509Certificate>
    try {
      clientCert = certStore.parsePEM(profile.certificate)
      caCerts = profile.caChain.map { certStore.parsePEM(it) }
    } catch (e: Exception) {
      throw PasspointSDKException("CERTIFICATE_PARSE_FAILED", "Failed to parse certificates: ${e.message}", e)
    }

    // 5. Load server CA
    val serverCaCert = loadServerCACert()

    // 6. Remove existing profiles
    hotspot.removeAll()

    // 7. Install new profile
    hotspot.install(HotspotConfigurator.ProfileConfig(
      domainName = profile.domainName,
      friendlyName = profile.friendlyName,
      naiRealmNames = profile.naiRealmNames,
      trustedServerNames = profile.trustedServerNames,
      clientCert = clientCert,
      caCerts = caCerts,
      serverCaCert = serverCaCert,
      keyPair = keyPair,
    ))

    // 8. Persist profile metadata for getCertificateInfo()
    prefs.edit()
      .putString(PREF_DOMAIN, profile.domainName)
      .putString(PREF_FRIENDLY_NAME, profile.friendlyName)
      .apply()
    Log.d(tag, "install: stored profile domain=${profile.domainName}")

    return JSONObject().put("success", true)
  }

  // MARK: - isInstalled

  fun isInstalled(): Boolean {
    return hotspot.isInstalled()
  }

  // MARK: - getCertificateInfo

  fun getCertificateInfo(): JSONObject {
    val result = JSONObject()

    if (!isInstalled()) {
      return result
        .put("isInstalled", false)
        .put("expiresAt", JSONObject.NULL)
        .put("subject", JSONObject.NULL)
        .put("domain", JSONObject.NULL)
        .put("friendlyName", JSONObject.NULL)
    }

    // We don't have direct access to the installed cert on Android
    // (it's inside the PasspointConfiguration), so we return what we know.
    val storedDomain = prefs.getString(PREF_DOMAIN, null)
    val storedFriendlyName = prefs.getString(PREF_FRIENDLY_NAME, null)
    result.put("isInstalled", true)
    result.put("expiresAt", JSONObject.NULL)
    result.put("subject", JSONObject.NULL)
    result.put("domain", storedDomain ?: JSONObject.NULL)
    result.put("friendlyName", storedFriendlyName ?: JSONObject.NULL)
    return result
  }

  // MARK: - getRemoteStatus

  /**
   * Returns the server-side profile status JSON, or null when the server has
   * no active profile for this subscriber (HTTP 404).
   */
  fun getRemoteStatus(subscriberId: String): JSONObject? {
    val apiKey = this.apiKey ?: throw PasspointSDKException("NOT_CONFIGURED", "SDK not configured")
    val baseUrl = this.baseUrl ?: throw PasspointSDKException("NOT_CONFIGURED", "SDK not configured")

    val encoded = URLEncoder.encode(subscriberId, "UTF-8")
    val url = URL("$baseUrl/preset/profile/status?subscriber_id=$encoded")
    val conn = (url.openConnection() as HttpURLConnection).apply {
      requestMethod = "GET"
      setRequestProperty("Accept", "application/json")
      setRequestProperty("X-Helium-P-Api-Key", apiKey)
      connectTimeout = 30_000
      readTimeout = 30_000
    }

    val code: Int
    try {
      code = conn.responseCode
    } catch (e: Exception) {
      throw PasspointSDKException("NETWORK_ERROR", "Failed to reach API: ${e.message}", e)
    }

    val stream = if (code in 200..299) conn.inputStream else conn.errorStream
    val body = stream?.bufferedReader()?.use { it.readText() } ?: ""

    return when (code) {
      in 200..299 -> {
        val json = JSONObject(body)
        JSONObject()
          .put("subscriberId", json.getString("subscriber_id"))
          .put("presetId", json.getString("preset_id"))
          .put("eapType", json.getInt("eap_type"))
          .put("expiresAt", json.getString("expires_at"))
          .put("active", json.getBoolean("active"))
      }
      404 -> null
      401, 403 -> throw PasspointSDKException("API_UNAUTHORIZED", "API key rejected: HTTP $code")
      429 -> throw PasspointSDKException("API_RATE_LIMITED", "Rate limited: HTTP $code")
      else -> throw PasspointSDKException("API_ERROR", "Status API error: HTTP $code $body")
    }
  }

  // MARK: - Remove

  fun remove(): JSONObject {
    if (apiKey == null) {
      throw PasspointSDKException("NOT_CONFIGURED", "SDK not configured")
    }

    hotspot.removeAll()
    keyStore.deleteKeyPair()
    prefs.edit()
      .remove(PREF_DOMAIN)
      .remove(PREF_FRIENDLY_NAME)
      .apply()

    return JSONObject().put("success", true)
  }

  // MARK: - Debug

  fun debug(): JSONObject {
    val info = JSONObject()
    info.put("configured", apiKey != null)
    info.put("baseUrl", baseUrl ?: JSONObject.NULL)
    info.put("eapType", eapType)
    info.put("presetId", presetId ?: JSONObject.NULL)
    info.put("profileDomain", prefs.getString(PREF_DOMAIN, null) ?: JSONObject.NULL)
    info.put("profileFriendlyName", prefs.getString(PREF_FRIENDLY_NAME, null) ?: JSONObject.NULL)
    info.put("platform", "android")
    info.put("apiLevel", android.os.Build.VERSION.SDK_INT)

    try {
      val kp = keyStore.getOrCreateKeyPair()
      info.put("hasKeyPair", true)
      info.put("keyType", kp.private.algorithm)
      info.put("keyEncodable", kp.private.encoded != null)
    } catch (e: Exception) {
      info.put("hasKeyPair", false)
      info.put("keyPairError", e.message)
    }

    info.put("isInstalled", hotspot.isInstalled())

    return info
  }

  // MARK: - Private

  private fun loadServerCACert(): X509Certificate {
    // Prefer custom PEM if provided
    val customPem = serverCaCertPem
    if (!customPem.isNullOrBlank()) {
      return certStore.parsePEM(customPem)
    }

    // Load from res/raw/helium_server_ca.crt
    val certFactory = CertificateFactory.getInstance("X.509")
    val resources = context.resources
    val resId = resources.getIdentifier("helium_server_ca", "raw", context.packageName)
    if (resId != 0) {
      resources.openRawResource(resId).use { stream ->
        return certFactory.generateCertificate(stream) as X509Certificate
      }
    }

    throw PasspointSDKException("CERTIFICATE_PARSE_FAILED",
      "helium_server_ca.crt not found in res/raw. Ensure the SDK resources are bundled.")
  }

  private fun fetchProfile(csr: String, subscriberId: String, apiKey: String, baseUrl: String): Profile {
    Log.d(tag, "fetchProfile: calling API")
    val url = URL("$baseUrl/preset/profile/generate")
    val conn = (url.openConnection() as HttpURLConnection).apply {
      requestMethod = "POST"
      doOutput = true
      setRequestProperty("Content-Type", "application/json")
      setRequestProperty("X-Helium-P-Api-Key", apiKey)
      connectTimeout = 30_000
      readTimeout = 30_000
    }

    val payload = JSONObject().apply {
      put("type", eapType)
      put("subscriber_id", subscriberId)
      put("csr", csr)
      presetId?.takeIf { it.isNotBlank() }?.let { put("preset_id", it) }
    }.toString()

    try {
      conn.outputStream.use { it.write(payload.toByteArray(Charsets.UTF_8)) }
    } catch (e: Exception) {
      throw PasspointSDKException("NETWORK_ERROR", "Failed to connect to API: ${e.message}", e)
    }

    val code = conn.responseCode
    val stream = if (code in 200..299) conn.inputStream else conn.errorStream
    val body = stream?.bufferedReader()?.use { it.readText() } ?: ""

    when (code) {
      in 200..299 -> {}
      401, 403 -> throw PasspointSDKException("API_UNAUTHORIZED", "API key rejected: HTTP $code")
      429 -> throw PasspointSDKException("API_RATE_LIMITED", "Rate limited: HTTP $code")
      else -> throw PasspointSDKException("API_ERROR", "Passpoint API error: HTTP $code $body")
    }

    val json = JSONObject(body)
    return Profile(
      friendlyName = json.getString("friendly_name"),
      domainName = json.getString("domain_name"),
      naiRealmNames = json.getJSONArray("nai_realm_names").toStringList(),
      trustedServerNames = json.getJSONArray("trusted_server_names").toStringList(),
      tlsVersion = json.optString("tls_version", "1.2"),
      certificate = json.getString("certificate"),
      caChain = json.getJSONArray("ca_chain").toStringList(),
    )
  }

  private fun JSONArray.toStringList(): List<String> {
    return (0 until length()).map { optString(it) }
  }
}
