package com.helium.passpoint

import android.Manifest
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod

class PasspointSDKModule(reactContext: ReactApplicationContext) :
  ReactContextBaseJavaModule(reactContext) {

  override fun getName(): String = "HeliumPasspointSDK"

  private val manager = PasspointManager(reactContext)
  private val mainHandler = Handler(Looper.getMainLooper())

  @ReactMethod
  fun configure(apiKey: String, endpoint: String, eapType: Int, serverCaCertPem: String?, keychainAccessGroup: String?) {
    // keychainAccessGroup is iOS-only, ignored on Android
    manager.configure(apiKey, endpoint, eapType, serverCaCertPem)
  }

  @ReactMethod
  fun install(userIdentifier: String, promise: Promise) {
    // Check location permission before proceeding
    val activity = reactApplicationContext.currentActivity
    if (activity != null &&
      ContextCompat.checkSelfPermission(activity, Manifest.permission.ACCESS_FINE_LOCATION)
        != PackageManager.PERMISSION_GRANTED
    ) {
      rejectOnMain(promise, "PERMISSION_DENIED",
        "ACCESS_FINE_LOCATION permission is required. Request it before calling install().")
      return
    }

    runAsync {
      try {
        val result = manager.install(userIdentifier)
        resolveOnMain(promise, result.toString())
      } catch (e: PasspointSDKException) {
        rejectOnMain(promise, e.errorCode, e.message ?: "Install failed")
      } catch (e: Exception) {
        rejectOnMain(promise, "UNKNOWN", e.message ?: "Install failed")
      }
    }
  }

  @ReactMethod
  fun isInstalled(promise: Promise) {
    runAsync {
      try {
        resolveOnMain(promise, manager.isInstalled())
      } catch (e: Exception) {
        rejectOnMain(promise, "UNKNOWN", e.message ?: "Check failed")
      }
    }
  }

  @ReactMethod
  fun getCertificateInfo(promise: Promise) {
    runAsync {
      try {
        val info = manager.getCertificateInfo()
        resolveOnMain(promise, info.toString())
      } catch (e: Exception) {
        rejectOnMain(promise, "UNKNOWN", e.message ?: "Failed to get certificate info")
      }
    }
  }

  @ReactMethod
  fun debug(promise: Promise) {
    runAsync {
      try {
        val info = manager.debug()
        resolveOnMain(promise, info.toString())
      } catch (e: Exception) {
        resolveOnMain(promise, "{\"error\": \"${e.message}\"}")
      }
    }
  }

  @ReactMethod
  fun remove(promise: Promise) {
    runAsync {
      try {
        val result = manager.remove()
        resolveOnMain(promise, result.toString())
      } catch (e: PasspointSDKException) {
        rejectOnMain(promise, e.errorCode, e.message ?: "Remove failed")
      } catch (e: Exception) {
        rejectOnMain(promise, "UNKNOWN", e.message ?: "Remove failed")
      }
    }
  }

  private fun runAsync(block: () -> Unit) {
    Thread { block() }.start()
  }

  private fun resolveOnMain(promise: Promise, value: Any) {
    mainHandler.post { promise.resolve(value) }
  }

  private fun rejectOnMain(promise: Promise, code: String, message: String) {
    mainHandler.post { promise.reject(code, message) }
  }
}
