package com.helium.passpoint.example

import android.Manifest
import android.os.Bundle
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import com.helium.passpoint.PasspointClient
import com.helium.passpoint.PasspointConfig
import com.helium.passpoint.PasspointEnvironment
import com.helium.passpoint.PasspointErrorCode
import com.helium.passpoint.PasspointException
import java.util.concurrent.Executors

/**
 * Minimal end-to-end example of the native Android SDK. The UI is built in code
 * so the example stays a single file — the SDK usage is what matters.
 */
class MainActivity : AppCompatActivity() {

  // Replace with your own values. subscriberId is whatever identifies the user
  // in your system; the SDK treats it as opaque.
  private val apiKey = "YOUR_PARTNER_API_KEY"
  private val subscriberId = "subscriber-123"

  private val client by lazy { PasspointClient.getInstance(this) }
  private val io = Executors.newSingleThreadExecutor()
  private lateinit var status: TextView

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    setContentView(buildLayout())

    client.configure(
      PasspointConfig(apiKey = apiKey, environment = PasspointEnvironment.Production)
    )

    // install() rejects with PERMISSION_DENIED until this is granted.
    ActivityCompat.requestPermissions(
      this,
      arrayOf(Manifest.permission.ACCESS_FINE_LOCATION),
      REQUEST_LOCATION,
    )

    refresh()
  }

  override fun onDestroy() {
    io.shutdown()
    super.onDestroy()
  }

  private fun refresh() = runInBackground {
    val info = client.getCertificateInfo()
    if (info.isInstalled) {
      "Installed\ndomain: ${info.domain}\nnetwork: ${info.friendlyName}"
    } else {
      "No Helium profile installed"
    }
  }

  private fun install() = runInBackground {
    client.install(subscriberId)
    "Installed for $subscriberId"
  }

  private fun remove() = runInBackground {
    client.remove()
    "Removed"
  }

  private fun checkServer() = runInBackground {
    when (val remote = client.getRemoteStatus(subscriberId)) {
      null -> "Server has no profile for $subscriberId"
      else -> "Server: active=${remote.active}, expires=${remote.expiresAt}"
    }
  }

  /**
   * The SDK's network and crypto calls block, so they must not run on the main
   * thread. Everything throws [PasspointException]; switch on [PasspointException.code]
   * to react to specific failures.
   */
  private fun runInBackground(block: () -> String) {
    status.text = "Working…"
    io.execute {
      val message = try {
        block()
      } catch (e: PasspointException) {
        when (e.code) {
          PasspointErrorCode.PERMISSION_DENIED -> "Grant location permission, then retry."
          PasspointErrorCode.API_UNAUTHORIZED -> "The API key was rejected."
          PasspointErrorCode.NETWORK_SUGGESTION_DISALLOWED ->
            "Allow this app to suggest Wi-Fi networks in Settings."
          else -> "${e.code}: ${e.message}"
        }
      }
      runOnUiThread { status.text = message }
    }
  }

  private fun buildLayout(): LinearLayout =
    LinearLayout(this).apply {
      orientation = LinearLayout.VERTICAL
      gravity = Gravity.CENTER
      setPadding(48, 48, 48, 48)

      status = TextView(this@MainActivity).apply { text = "…" }
      addView(status)

      addView(button("Install profile") { install() })
      addView(button("Refresh") { refresh() })
      addView(button("Check server status") { checkServer() })
      addView(button("Remove profile") { remove() })
    }

  private fun button(label: String, onClick: () -> Unit): Button =
    Button(this).apply {
      text = label
      setOnClickListener { onClick() }
    }

  private companion object {
    const val REQUEST_LOCATION = 1001
  }
}
