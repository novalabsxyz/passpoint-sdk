package com.helium.passpoint

import android.os.Handler
import android.os.Looper
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import java.util.concurrent.ExecutorService
import java.util.concurrent.SynchronousQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import org.json.JSONObject

/**
 * React Native bridge. Everything below is translation only — argument
 * unpacking, JSON encoding and promise plumbing. The behaviour lives in
 * [PasspointClient] (core/kotlin/), which the native Android SDK exposes
 * directly.
 *
 * There is no dependency declaration for the core here: `android/build.gradle`
 * compiles the core sources into this module, which is also what lets the
 * bridge reuse the core's internal [Iso8601] formatter so the timestamps
 * TypeScript receives match the ones the native SDKs produce.
 */
class PasspointSDKModule(reactContext: ReactApplicationContext) :
  ReactContextBaseJavaModule(reactContext) {

  override fun getName(): String = NAME

  private val client = PasspointClient.getInstance(reactContext)
  private val mainHandler = Handler(Looper.getMainLooper())

  // PasspointClient's blocking methods must not run on the RN JS or UI thread.
  // A cached pool, not a single worker: isInstalled()/getCertificateInfo()/
  // debug() are cheap reads that a UI polls during a 60-second install, and
  // queueing them behind it would stall the screen. Idle threads retire after
  // 60s, so there is no lifecycle hook to call — `invalidate()` and
  // `onCatalystInstanceDestroy()` exist on different React Native versions and
  // this module supports 0.73 through current.
  private val worker: ExecutorService = ThreadPoolExecutor(
    0, Integer.MAX_VALUE, 60L, TimeUnit.SECONDS, SynchronousQueue(),
  ) { runnable -> Thread(runnable, "helium-passpoint").apply { isDaemon = true } }

  @ReactMethod
  @Suppress("UNUSED_PARAMETER")
  fun configure(
    apiKey: String,
    baseUrl: String,
    eapType: Int,
    serverCaCertPem: String?,
    keychainAccessGroup: String?,
    presetId: String?,
  ) {
    // keychainAccessGroup is iOS-only. The TypeScript layer has already
    // resolved `environment` to a full URL.
    client.configure(
      PasspointConfig(
        apiKey = apiKey,
        environment = PasspointEnvironment.named(baseUrl),
        eapType = runCatching { EapType.fromValue(eapType) }.getOrDefault(EapType.TLS),
        serverCaCertPem = serverCaCertPem,
        presetId = presetId,
      )
    )
  }

  @ReactMethod
  fun install(subscriberId: String, promise: Promise) {
    resolveJson(promise) {
      client.install(subscriberId)
      JSONObject().put("success", true)
    }
  }

  @ReactMethod
  fun isInstalled(promise: Promise) {
    resolve(promise) { client.isInstalled() }
  }

  @ReactMethod
  fun getCertificateInfo(promise: Promise) {
    resolveJson(promise) {
      val info = client.getCertificateInfo()
      JSONObject()
        .put("isInstalled", info.isInstalled)
        .put("expiresAt", info.expiresAt?.let { Iso8601.format(it) } ?: JSONObject.NULL)
        .put("subject", info.subject ?: JSONObject.NULL)
        .put("domain", info.domain ?: JSONObject.NULL)
        .put("friendlyName", info.friendlyName ?: JSONObject.NULL)
    }
  }

  @ReactMethod
  fun getRemoteStatus(subscriberId: String, promise: Promise) {
    resolve(promise) {
      val status = client.getRemoteStatus(subscriberId) ?: return@resolve "null"
      JSONObject()
        .put("subscriberId", status.subscriberId)
        .put("presetId", status.presetId)
        .put("eapType", status.eapType)
        // The server's exact string, not a reformatted one — the TypeScript
        // layer surfaces it verbatim.
        .put("expiresAt", status.expiresAtRaw)
        .put("active", status.active)
        .toString()
    }
  }

  @ReactMethod
  fun remove(promise: Promise) {
    resolveJson(promise) {
      client.remove()
      JSONObject().put("success", true)
    }
  }

  @ReactMethod
  fun debug(promise: Promise) {
    worker.execute {
      // debug() must never fail — it is what support asks for when things break.
      val json = try {
        JSONObject(client.diagnostics()).toString()
      } catch (e: Exception) {
        JSONObject().put("error", e.message ?: "failed to collect diagnostics").toString()
      }
      mainHandler.post { promise.resolve(json) }
    }
  }

  // MARK: - Bridge plumbing

  private fun resolveJson(promise: Promise, block: () -> JSONObject) {
    resolve(promise) { block().toString() }
  }

  private fun <T : Any> resolve(promise: Promise, block: () -> T) {
    worker.execute {
      try {
        val value = block()
        mainHandler.post { promise.resolve(value) }
      } catch (e: PasspointException) {
        // Reject with the contract error code so PasspointError.fromNative in
        // TypeScript can map it back to a PasspointErrorCode.
        rejectOnMain(promise, e.code.name, e.message)
      } catch (e: Exception) {
        rejectOnMain(promise, PasspointErrorCode.UNKNOWN.name, e.message ?: "Unknown error")
      }
    }
  }

  private fun rejectOnMain(promise: Promise, code: String, message: String) {
    mainHandler.post { promise.reject(code, message) }
  }

  companion object {
    const val NAME = "HeliumPasspointSDK"
  }
}
