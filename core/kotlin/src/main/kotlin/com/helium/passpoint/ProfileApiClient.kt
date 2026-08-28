package com.helium.passpoint

import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import org.json.JSONArray
import org.json.JSONObject

/** One HTTP request, independent of any particular client library. */
internal data class HttpRequest(
  val url: String,
  val method: String,
  val headers: Map<String, String> = emptyMap(),
  val body: ByteArray? = null,
) {
  // Generated equals/hashCode would compare ByteArray by identity.
  override fun equals(other: Any?): Boolean =
    other is HttpRequest &&
      url == other.url &&
      method == other.method &&
      headers == other.headers &&
      (body?.contentEquals(other.body ?: ByteArray(0)) ?: (other.body == null))

  override fun hashCode(): Int =
    (((url.hashCode() * 31) + method.hashCode()) * 31 + headers.hashCode()) * 31 +
      (body?.contentHashCode() ?: 0)
}

internal data class HttpResponse(val statusCode: Int, val body: String)

/** Seam that lets the API client be tested without a network. */
internal interface HttpTransport {
  /** @throws java.io.IOException on transport failure; the caller maps it to NETWORK_ERROR. */
  fun send(request: HttpRequest): HttpResponse
}

/** Production transport, on the JDK's built-in client so the AAR stays dependency-light. */
internal class HttpUrlConnectionTransport(
  private val connectTimeoutMs: Int = 30_000,
  private val readTimeoutMs: Int = 30_000,
) : HttpTransport {
  override fun send(request: HttpRequest): HttpResponse {
    val connection = (URL(request.url).openConnection() as HttpURLConnection).apply {
      requestMethod = request.method
      connectTimeout = connectTimeoutMs
      readTimeout = readTimeoutMs
      request.headers.forEach { (name, value) -> setRequestProperty(name, value) }
      if (request.body != null) doOutput = true
    }

    try {
      request.body?.let { payload -> connection.outputStream.use { it.write(payload) } }
      val status = connection.responseCode
      val stream = if (status in 200..299) connection.inputStream else connection.errorStream
      val body = stream?.bufferedReader()?.use { it.readText() } ?: ""
      return HttpResponse(status, body)
    } finally {
      connection.disconnect()
    }
  }
}

/**
 * Talks to the Helium inventory API. Contains no Android-specific code, so the
 * unit tests exercise it directly through a fake [HttpTransport].
 */
internal class ProfileApiClient(
  private val baseUrl: String,
  private val apiKey: String,
  private val transport: HttpTransport = HttpUrlConnectionTransport(),
) {
  companion object {
    const val API_KEY_HEADER = "X-Helium-P-Api-Key"
    const val GENERATE_PROFILE_PATH = "preset/profile/generate"
    const val PROFILE_STATUS_PATH = "preset/profile/status"
    const val STATUS_SUBSCRIBER_QUERY_PARAM = "subscriber_id"

    /**
     * RFC 3986 percent-encoding for a query value. [URLEncoder] is
     * form-encoding: it emits `+` for a space, which a server reading the query
     * string decodes back to a space only by convention. Normalising here keeps
     * the URL identical to the one the iOS SDK builds for the same input.
     */
    fun encodeQueryValue(value: String): String =
      URLEncoder.encode(value, "UTF-8")
        .replace("+", "%20")
        .replace("*", "%2A")
        .replace("%7E", "~")

    /** Maps HTTP status to error codes exactly as `contract.json` prescribes. */
    fun throwIfErrorStatus(status: Int, body: String) {
      if (status in 200..299) return
      when (status) {
        401, 403 ->
          throw PasspointException(
            PasspointErrorCode.API_UNAUTHORIZED,
            "API key was rejected (unauthorized).",
          )
        429 ->
          throw PasspointException(
            PasspointErrorCode.API_RATE_LIMITED,
            "Passpoint API rate limit exceeded: HTTP $status",
          )
        else ->
          throw PasspointException(
            PasspointErrorCode.API_ERROR,
            "Passpoint API error: HTTP $status: $body",
          )
      }
    }
  }

  private val root = baseUrl.trimEnd('/')

  /** Exchange a CSR for a signed Passpoint profile. */
  fun generateProfile(
    csr: String,
    subscriberId: String,
    eapType: EapType,
    presetId: String?,
  ): IssuedProfile {
    val payload = JSONObject().apply {
      put("type", eapType.value)
      put("subscriber_id", subscriberId)
      put("csr", csr)
      presetId?.takeIf { it.isNotBlank() }?.let { put("preset_id", it) }
    }

    val response = perform(
      HttpRequest(
        url = "$root/$GENERATE_PROFILE_PATH",
        method = "POST",
        headers = mapOf(
          API_KEY_HEADER to apiKey,
          "Content-Type" to "application/json",
          "Accept" to "application/json",
        ),
        body = payload.toString().toByteArray(Charsets.UTF_8),
      )
    )
    throwIfErrorStatus(response.statusCode, response.body)

    return try {
      val json = JSONObject(response.body)
      IssuedProfile(
        friendlyName = json.getString("friendly_name"),
        domainName = json.getString("domain_name"),
        naiRealmNames = json.getJSONArray("nai_realm_names").toStringList(),
        trustedServerNames = json.getJSONArray("trusted_server_names").toStringList(),
        tlsVersion = json.optString("tls_version", "1.2").ifBlank { "1.2" },
        certificate = json.getString("certificate"),
        caChain = json.getJSONArray("ca_chain").toStringList(),
      )
    } catch (e: PasspointException) {
      throw e
    } catch (e: Exception) {
      throw PasspointException(
        PasspointErrorCode.API_ERROR,
        "Failed to decode profile: ${e.message}",
        e,
      )
    }
  }

  /**
   * Server-side status for a subscriber, or null when the server has no profile
   * for them (HTTP 404).
   */
  fun profileStatus(subscriberId: String): RemoteProfileStatus? {
    val encoded = encodeQueryValue(subscriberId)
    val response = perform(
      HttpRequest(
        url = "$root/$PROFILE_STATUS_PATH?$STATUS_SUBSCRIBER_QUERY_PARAM=$encoded",
        method = "GET",
        headers = mapOf(API_KEY_HEADER to apiKey, "Accept" to "application/json"),
      )
    )
    if (response.statusCode == 404) return null
    throwIfErrorStatus(response.statusCode, response.body)

    return try {
      val json = JSONObject(response.body)
      val rawExpiry = json.getString("expires_at")
      RemoteProfileStatus(
        subscriberId = json.getString("subscriber_id"),
        presetId = json.getString("preset_id"),
        eapType = json.getInt("eap_type"),
        expiresAt = Iso8601.parse(rawExpiry),
        expiresAtRaw = rawExpiry,
        active = json.getBoolean("active"),
      )
    } catch (e: PasspointException) {
      throw e
    } catch (e: Exception) {
      throw PasspointException(
        PasspointErrorCode.API_ERROR,
        "Failed to decode status: ${e.message}",
        e,
      )
    }
  }

  // MARK: - Private

  private fun perform(request: HttpRequest): HttpResponse =
    try {
      transport.send(request)
    } catch (e: PasspointException) {
      throw e
    } catch (e: Exception) {
      throw PasspointException(
        PasspointErrorCode.NETWORK_ERROR,
        "Network error: ${e.message}",
        e,
      )
    }

  // optString, not getString: a null entry in the array yields "" rather than
  // aborting the install with a JSONException.
  private fun JSONArray.toStringList(): List<String> = (0 until length()).map { optString(it) }
}
