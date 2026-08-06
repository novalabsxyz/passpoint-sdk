package com.helium.passpoint

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import androidx.annotation.WorkerThread
import androidx.core.content.ContextCompat
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * Entry point to the Helium Passpoint SDK.
 *
 * ```kotlin
 * val client = PasspointClient.getInstance(context)
 * client.configure(PasspointConfig(apiKey = "…"))
 * // install() blocks on network and crypto — never call it on the main thread.
 * withContext(Dispatchers.IO) { client.install("subscriber-123") }
 * ```
 *
 * **Permissions.** [install] requires `ACCESS_FINE_LOCATION` to have been
 * granted at runtime; it throws [PasspointErrorCode.PERMISSION_DENIED]
 * otherwise. The SDK declares the manifest permissions it needs, but Android
 * requires the *app* to prompt for the dangerous ones.
 *
 * **Threading.** Methods annotated [WorkerThread] perform network and
 * cryptographic work synchronously — never call them on the main thread. The
 * instance is safe to use from several threads: [install] and [remove] are
 * serialised against each other, and the read-only queries are not gated so
 * they stay responsive during an install.
 */
class PasspointClient(context: Context) {
  private val appContext = context.applicationContext
  private val keyStore = KeyStoreManager(appContext)
  private val csrGenerator = CsrGenerator()
  private val certStore = CertificateStore()
  private val hotspot by lazy { HotspotConfigurator(appContext) }
  private val prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

  @Volatile private var config: PasspointConfig? = null

  /**
   * Serialises [install] and [remove]: they touch the same keypair and profile,
   * so interleaving them can leave a half-provisioned device. The read-only
   * queries are deliberately not gated and stay responsive during an install.
   */
  private val operationLock = ReentrantLock()

  companion object {
    private const val TAG = "PasspointClient"
    private const val PREFS_NAME = "helium_passpoint_manager"
    private const val PREF_DOMAIN = "profile_domain"
    private const val PREF_FRIENDLY_NAME = "profile_friendly_name"

    /** Name of the bundled CA in `res/raw`, used when no custom PEM is configured. */
    const val SERVER_CA_RESOURCE = "helium_server_ca"

    @Volatile private var instance: PasspointClient? = null

    /**
     * Process-wide instance, matching the singleton the React Native bridge and
     * the iOS `PasspointClient.shared` use. Apps that prefer to own the
     * lifetime can use the constructor instead.
     */
    @JvmStatic
    fun getInstance(context: Context): PasspointClient =
      instance ?: synchronized(this) {
        instance ?: PasspointClient(context).also { instance = it }
      }
  }

  // MARK: - Configuration

  /**
   * Store the SDK configuration. Must be called before anything else.
   *
   * @throws PasspointException with [PasspointErrorCode.INVALID_CONFIG] if `apiKey` is blank.
   */
  fun configure(config: PasspointConfig) {
    this.config = config.validated().requireAndroidSupported()
    Log.d(TAG, "configured: baseUrl=${config.environment.baseUrl}, eapType=${config.eapType.value}")
  }

  /** Whether [configure] has been called successfully. */
  val isConfigured: Boolean
    get() = config != null

  // MARK: - Install

  /**
   * Provision a Passpoint profile for [subscriberId].
   *
   * Generates an RSA-2048 keypair, sends a CSR to the Helium inventory API,
   * and installs the returned certificate chain as a Passpoint profile. Any
   * profile previously installed by this SDK is removed first, so a device only
   * ever holds one Helium credential.
   *
   * @param subscriberId Partner-defined subscriber identifier. Opaque to the
   *   SDK; the server revokes any prior certificate issued for it.
   * @throws PasspointException on any failure; inspect [PasspointException.code].
   */
  @WorkerThread
  fun install(subscriberId: String) {
    val config = requireConfig()
    requireSubscriberId(subscriberId)
    requireLocationPermission()
    operationLock.withLock { performInstall(subscriberId, config) }
  }

  private fun performInstall(subscriberId: String, config: PasspointConfig) {
    // Only one Helium credential may exist at a time.
    hotspot.removeAll()
    keyStore.deleteKeyPair()

    val keyPair = try {
      keyStore.getOrCreateKeyPair()
    } catch (e: Exception) {
      throw PasspointException(
        PasspointErrorCode.KEYPAIR_GENERATION_FAILED,
        "Failed to get or create keypair: ${e.message}",
        e,
      )
    }

    val csr = csrGenerator.generate(subscriberId, keyPair)
    val profile = apiClient(config).generateProfile(
      csr = csr,
      subscriberId = subscriberId,
      eapType = config.eapType,
      presetId = config.presetId,
    )

    val clientCert = certStore.parsePem(profile.certificate)
    val caCerts = profile.caChain.map { certStore.parsePem(it) }
    val serverCaCert = loadServerCaCert(config)

    hotspot.install(
      HotspotConfigurator.ProfileConfig(
        domainName = profile.domainName,
        friendlyName = profile.friendlyName,
        naiRealmNames = profile.naiRealmNames,
        trustedServerNames = profile.trustedServerNames,
        clientCert = clientCert,
        caCerts = caCerts,
        serverCaCert = serverCaCert,
        keyPair = keyPair,
      )
    )

    // Remembered so getCertificateInfo() can report the profile's own domain
    // and name rather than the inventory API host.
    prefs.edit()
      .putString(PREF_DOMAIN, profile.domainName)
      .putString(PREF_FRIENDLY_NAME, profile.friendlyName)
      .apply()
    Log.d(TAG, "install: stored profile domain=${profile.domainName}")
  }

  // MARK: - Queries

  /** Whether a Helium Passpoint credential is installed on this device. */
  fun isInstalled(): Boolean = hotspot.isInstalled()

  /**
   * Details of the installed credential. Returns [CertificateInfo.NOT_INSTALLED]
   * rather than throwing when there is none.
   *
   * Android does not expose the certificate inside an installed
   * `PasspointConfiguration`, so `expiresAt` and `subject` are always null —
   * see [CertificateInfo].
   */
  fun getCertificateInfo(): CertificateInfo {
    if (!isInstalled()) return CertificateInfo.NOT_INSTALLED
    return CertificateInfo(
      isInstalled = true,
      expiresAt = null,
      subject = null,
      domain = prefs.getString(PREF_DOMAIN, null),
      friendlyName = prefs.getString(PREF_FRIENDLY_NAME, null),
    )
  }

  /**
   * The server's view of a subscriber's profile.
   *
   * Unlike [isInstalled] this hits the network, so it detects server-side
   * revocation and confirms an install landed end to end.
   *
   * @return null when the server has no profile for [subscriberId].
   */
  @WorkerThread
  fun getRemoteStatus(subscriberId: String): RemoteProfileStatus? {
    val config = requireConfig()
    requireSubscriberId(subscriberId)
    return apiClient(config).profileStatus(subscriberId)
  }

  // MARK: - Remove

  /** Remove the Passpoint profile and delete the stored keypair. */
  @WorkerThread
  fun remove() {
    requireConfig()
    operationLock.withLock {
      hotspot.removeAll()
      keyStore.deleteKeyPair()
      prefs.edit().remove(PREF_DOMAIN).remove(PREF_FRIENDLY_NAME).apply()
    }
  }

  // MARK: - Diagnostics

  /**
   * Support-facing snapshot of SDK state. Never contains the API key.
   * The shape is not part of the SDK's compatibility promise.
   */
  fun diagnostics(): Map<String, String> {
    val current = config
    val info = linkedMapOf(
      "configured" to (current != null).toString(),
      "baseUrl" to (current?.environment?.baseUrl ?: "nil"),
      "eapType" to (current?.eapType?.value?.toString() ?: "nil"),
      "presetId" to (current?.presetId ?: "nil"),
      "profileDomain" to (prefs.getString(PREF_DOMAIN, null) ?: "nil"),
      "profileFriendlyName" to (prefs.getString(PREF_FRIENDLY_NAME, null) ?: "nil"),
      "platform" to "android",
      "apiLevel" to android.os.Build.VERSION.SDK_INT.toString(),
      "hasLocationPermission" to hasLocationPermission().toString(),
      "hasKeyPair" to keyStore.hasKeyPair().toString(),
    )

    // Both are set reflectively into @hide members and can silently no-op on
    // API 28+; a support ticket needs to know which happened.
    val (statusCheck, trustedNames) = hotspot.serverValidationApplied()
    info["aaaServerCertStatusCheck"] = statusCheck.toString()
    info["aaaServerTrustedNames"] = trustedNames.toString()
    info["isInstalled"] = try {
      hotspot.isInstalled().toString()
    } catch (e: Exception) {
      "error: ${e.message}"
    }
    return info
  }

  // MARK: - Private

  private fun requireConfig(): PasspointConfig =
    config
      ?: throw PasspointException(
        PasspointErrorCode.NOT_CONFIGURED,
        "SDK has not been configured. Call configure() first.",
      )

  private fun requireSubscriberId(subscriberId: String) {
    if (subscriberId.isBlank()) {
      throw PasspointException(
        PasspointErrorCode.INVALID_CONFIG,
        "subscriberId is required and must be non-empty.",
      )
    }
  }

  private fun hasLocationPermission(): Boolean =
    ContextCompat.checkSelfPermission(appContext, Manifest.permission.ACCESS_FINE_LOCATION) ==
      PackageManager.PERMISSION_GRANTED

  private fun requireLocationPermission() {
    if (!hasLocationPermission()) {
      throw PasspointException(
        PasspointErrorCode.PERMISSION_DENIED,
        "ACCESS_FINE_LOCATION is required for Passpoint. Request it before calling install().",
      )
    }
  }

  private fun apiClient(config: PasspointConfig) =
    ProfileApiClient(baseUrl = config.environment.baseUrl, apiKey = config.apiKey)

  private fun loadServerCaCert(config: PasspointConfig): X509Certificate {
    config.serverCaCertPem?.takeIf { it.isNotBlank() }?.let { return certStore.parsePem(it) }

    val resources = appContext.resources
    val resId = resources.getIdentifier(SERVER_CA_RESOURCE, "raw", appContext.packageName)
    if (resId != 0) {
      try {
        resources.openRawResource(resId).use { stream ->
          return CertificateFactory.getInstance("X.509").generateCertificate(stream)
            as X509Certificate
        }
      } catch (e: Exception) {
        throw PasspointException(
          PasspointErrorCode.CERTIFICATE_PARSE_FAILED,
          "Failed to read bundled $SERVER_CA_RESOURCE: ${e.message}",
          e,
        )
      }
    }

    throw PasspointException(
      PasspointErrorCode.CERTIFICATE_PARSE_FAILED,
      "$SERVER_CA_RESOURCE.crt not found in res/raw. Ensure the SDK resources are bundled.",
    )
  }
}
