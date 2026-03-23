package com.helium.passpoint

import android.content.Context
import android.util.Log
import java.net.HttpURLConnection
import java.net.URL
import java.security.KeyPair
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import org.json.JSONArray
import org.json.JSONObject

class PasspointManager(private val context: Context) {
  private val tag = "PasspointManager"

  private var apiKey: String? = null
  private var endpoint: String? = null
  private var eapType: Int = 13
  private var serverCaCertPem: String? = null
  private var domain: String? = null

  private val keyStore = KeyStoreManager()
  private val csrGenerator = CSRGenerator()
  private val certStore = CertificateStore()
  private val hotspot by lazy { HotspotConfigurator(context) }

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

  fun configure(apiKey: String, endpoint: String, eapType: Int, serverCaCertPem: String?) {
    this.apiKey = apiKey
    this.endpoint = endpoint
    this.eapType = eapType
    this.serverCaCertPem = serverCaCertPem
    this.domain = try { URL(endpoint).host } catch (_: Exception) { null }
    Log.d(tag, "configured: endpoint=$endpoint, eapType=$eapType, domain=$domain")
  }

  // MARK: - Install

  fun install(userIdentifier: String): JSONObject {
    val apiKey = this.apiKey ?: throw PasspointSDKException("NOT_CONFIGURED", "SDK not configured")
    val endpoint = this.endpoint ?: throw PasspointSDKException("NOT_CONFIGURED", "SDK not configured")
    val domain = this.domain ?: throw PasspointSDKException("NOT_CONFIGURED", "Domain not resolved from endpoint")

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
      csr = csrGenerator.generate(userIdentifier, domain, keyPair)
    } catch (e: Exception) {
      throw PasspointSDKException("CSR_GENERATION_FAILED", "Failed to generate CSR: ${e.message}", e)
    }

    // 3. Call API
    val profile = fetchProfile(csr, apiKey, endpoint)

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
      clientCert = clientCert,
      caCerts = caCerts,
      serverCaCert = serverCaCert,
      keyPair = keyPair,
    ))

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
    result.put("isInstalled", true)
    result.put("expiresAt", JSONObject.NULL)
    result.put("subject", JSONObject.NULL)
    result.put("domain", domain ?: JSONObject.NULL)
    result.put("friendlyName", "Helium WiFi")
    return result
  }

  // MARK: - Revoke

  fun revoke(): JSONObject {
    if (apiKey == null) {
      throw PasspointSDKException("NOT_CONFIGURED", "SDK not configured")
    }

    // TODO: Call server-side revocation API once endpoint is defined

    // Local cleanup
    hotspot.removeAll()
    keyStore.deleteKeyPair()

    return JSONObject().put("success", true)
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

  private fun fetchProfile(csr: String, apiKey: String, endpoint: String): Profile {
    Log.d(tag, "fetchProfile: calling API")
    val url = URL(endpoint)
    val conn = (url.openConnection() as HttpURLConnection).apply {
      requestMethod = "POST"
      doOutput = true
      setRequestProperty("Content-Type", "application/json")
      setRequestProperty("X-Helium-P-Api-Key", apiKey)
      connectTimeout = 30_000
      readTimeout = 30_000
    }

    val payload = JSONObject().apply {
      put("csr", csr)
      put("type", eapType)
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
