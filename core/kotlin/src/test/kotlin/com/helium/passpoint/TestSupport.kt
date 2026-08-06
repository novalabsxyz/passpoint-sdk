package com.helium.passpoint

import java.io.File
import java.security.KeyPair
import java.security.KeyPairGenerator
import org.json.JSONObject

/**
 * Locates `core/testdata/`, the fixture directory shared with the Swift and
 * TypeScript suites. `repoRoot` is set by `core/kotlin/build.gradle.kts` so this
 * does not depend on the test task's working directory.
 */
object Fixtures {
  private val repoRoot: File =
    File(
      System.getProperty("repoRoot")
        ?: error("repoRoot system property not set; see core/kotlin/build.gradle.kts")
    )

  val directory: File = File(repoRoot, "core/testdata")

  fun text(name: String): String = File(directory, name).readText()

  /** `core/contract/contract.json`, the cross-SDK source of truth. */
  fun contract(): JSONObject = JSONObject(File(repoRoot, "core/contract/contract.json").readText())
}

object TestKeys {
  fun rsaKeyPair(bits: Int = 2048): KeyPair =
    KeyPairGenerator.getInstance("RSA").apply { initialize(bits) }.generateKeyPair()
}

/** Canned [HttpTransport] for exercising [ProfileApiClient] without a network. */
internal class FakeTransport(private val outcomes: MutableList<Outcome>) : HttpTransport {
  sealed class Outcome {
    data class Reply(val status: Int, val body: String) : Outcome()
    data class Fail(val error: Exception) : Outcome()
  }

  constructor(status: Int, body: String) : this(mutableListOf(Outcome.Reply(status, body)))
  constructor(error: Exception) : this(mutableListOf(Outcome.Fail(error)))

  val requests = mutableListOf<HttpRequest>()
  val lastRequest: HttpRequest?
    get() = requests.lastOrNull()

  override fun send(request: HttpRequest): HttpResponse {
    requests.add(request)
    check(outcomes.isNotEmpty()) { "FakeTransport ran out of outcomes" }
    return when (val outcome = outcomes.removeAt(0)) {
      is Outcome.Fail -> throw outcome.error
      is Outcome.Reply -> HttpResponse(outcome.status, outcome.body)
    }
  }
}

/** Assert that [block] throws a [PasspointException] carrying [code]. */
internal inline fun assertThrowsPasspoint(code: PasspointErrorCode, block: () -> Unit) {
  try {
    block()
  } catch (e: PasspointException) {
    if (e.code != code) throw AssertionError("expected $code but got ${e.code}: ${e.message}")
    return
  }
  throw AssertionError("expected PasspointException($code), but nothing was thrown")
}
